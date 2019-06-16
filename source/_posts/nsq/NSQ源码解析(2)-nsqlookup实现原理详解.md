title: NSQ源码解析(2)-nsqlookup实现原理详解
layout: post
date: 2018-02-20 16:49:32
comments: true
categories: NSQ源码解析
tags: 
    - 源码解析
    - NSQ
    - golang
    - 消息队列
    
keywords: “NSQ”, "缓存机制"
description: 在使用NSQ的时候，首先需要启动nsqlookup. nsqlookup是管理中心，负责管理拓扑信息。nsqd节点在启动的时候会向nsqlookup进行注册，并且nsqd节点通过nsqlookup广播话题（topic）和通道（channel）信息。消费者通过查询nsqlookupd来发现指定话题（topic）的nsqd，并与nsqd建立连接进行通信和订阅。nsqlookupd类似于kafka中的zookeeper和Spring cloud中的注册中心。本文分析nsqlookupd如何进行管理集群中的拓扑关系，以及nsqlookupd的实现机制。

---

在使用NSQ的时候，首先需要启动nsqlookup. nsqlookup是管理中心，负责管理拓扑信息。nsqd节点在启动的时候会向nsqlookup进行注册，并且nsqd节点通过nsqlookup广播话题（topic）和通道（channel）信息。消费者通过查询nsqlookupd来发现指定话题（topic）的nsqd，并与nsqd建立连接进行通信和订阅。nsqlookupd类似于kafka中的zookeeper和Spring cloud中的注册中心。本文分析nsqlookupd如何进行管理集群中的拓扑关系，以及nsqlookupd的实现机制。

这篇文章主要从以下几个方面来分析下nsqlookupd源码：

 - nsqlookupd设计原理
   - 整体架构
   - 数据结构。采用什么数据结构存储和维护注册信息
   - 注册表的管理，如何进行管理
 - nsqlookupd运行过程--分析了启动过程 
 - nsqlookupd源码实现
 - 总结


# 一. 设计原理
## 1.1 整体架构
首先我们看看nsqlookupd的整体架构，它是如何启动相关服务、管理客户端请求、如何接受客户端请求并处理？

nsqlookupd提供了两种请求方式：

 1. 基于http的方式
 2. 基于tcp的方式

nsqlookupd/nsqlookupd.go 代码定义了NSQLookupd结构，NSQLookupd表示了nsqlookupd服务实例，它完成了http和tcp的监听和启动，初始化并维护了registrationMap注册表。可以理解它表示了整个nsqlookupd服务的核心，其结构如下:
  
```
type NSQLookupd struct {
    sync.RWMutex				           // 读写锁
    opts         *Options		         // nsqlookup配置
    tcpListener  net.Listener           // 监听的tcp服务
    httpListener net.Listener           // 监听的http服务
    waitGroup    util.WaitGroupWrapper  // 用于等待goroutine结束
    DB           *RegistrationDB        // 注册数据库，存放着topic和producer的映射关系注册表
}
```
 
![](/images/15191070428068.jpg)
 
 上图是这些元素的关系图，NSQLookupd有两个服务http服务和tcp服务:
 
  - http服务处理REST API请求. httpListener负责监听http请求，根据请求的url交给httpServer的对应函数去处理。
  - tcp服务不断轮询，当tcpListener接受到了tcp请求后，就交给TCPHandler处理。


### 1.1.1 HTTP 
HTTP提供了以下接口:

| 接口 | 功能 |
| --- | --- |
| GET /lookup | 返回某个topic下所有的producers |
| GET /topics | 获取所有的topic |
| GET /channels | 获取所有的channels |
| GET /nodes | 获取所有的节点 |
| POST /create_topic | 创建topic， 这里只是创建topic而不会添加该topic的producer  |
| POST /delete_topic | 删除topic |
| POST /create_channel | 创建channel, 也不会添加producer |
| POST /delete_channel | 删除channel |
| POST /topic/tombstone |  |
| GET /ping | 心跳检测，返回OK |
| GET /info | 获取版本信息 |

### 1.1.2 TCP 
nsqlookupd的tcp协议格式如下：

```
|   protocolMagic(4-byte) | 
|  命令 [参数]             |  // 长度不定，一行代表一个命令)
|  命令 [参数]             |
|  .....                  |
|  命令 [参数]             |
```

tcp消息的前4个字节是存放客户端的版本，也叫做协议的魔数protocolMagic，这个为了向下兼容而设计的。根据这个protocolMagic选择对应的该版本处理方式。目前只支持“ V1”: 

```
switch protocolMagic {
case "  V1":
	prot = &LookupProtocolV1{ctx: p.ctx}
default:
	// 其他协议则发送E_BAD_PROTOCOL并关闭连接并
	protocol.SendResponse(clientConn, []byte("E_BAD_PROTOCOL"))
	clientConn.Close()
	p.ctx.nsqlookupd.logf(LOG_ERROR, "client(%s) bad protocol magic '%s'",
		clientConn.RemoteAddr(), protocolMagic)
	return
}
```

后面的数据则是客户端的请求命令，一行对应一个命令。tcp方式提供了4中操作，命令包括:

 - PING: 心跳检测，nsqd每隔一段时间都会向nsqlookupd发送心跳
 - IDENTIFY: 身份识别, 当nsqd第一次连接nsqlookupd时，发送IDENTITY验证自己身份
 - REGISTER: 注册topic和channel, **这里会将客户端的信息设置到注册表中**.
 - UNREGISTER: 撤销topic或channel.

下面是nsqlookupd的tcp协议案例：

```
V1 
IDENTIFY 
PING
REGISTER topic1 channel1
REGISTER topic1 channel2
UNREGISTER topic2 
```

## 1.2 数据结构
### 1.2.1 注册表
nsqlookup的主要任务是负责注册和管理各个客户端，管理客户端与topic、Channel之间的关系。为了维护这种关系，在nsqlookup内部提供了一张注册表，这张注册表使用**RegistrationDB**结构来实现。注册表的实现在 nsqlookupd/registration_db.go 文件中:

```
type RegistrationDB struct {
	sync.RWMutex                               // 读写锁
	registrationMap map[Registration]Producers // 注册表
}

// 注册表的key, 
type Registration struct {
	Category string   // 这个用来指定key的类型，比如是topic或者channel
	Key      string   // 存放定义的topic值
	SubKey   string   // 如果是channel类型，存放channel值
}

// 生产者列表
type Producers []*Producer
```

sync.RWMutex 是为了保证registrationMap线程安全而设置的一个读写锁。
registrationMap是注册表，维护着Topic或Channel与Producers。一个Topic或Channel对应多个Producers。

注册表registrationMap维护着Registration和Producers之间的关系。Registration可以看做是注册信息的一个key值，一个Registration可以对应多个Producers.

### 1.2.2 Registration构建
这个key是如何生成的呢？由那些元素决定。在golang中，可以使用结构体struct做map的key，key的比较是比较struct中的每个属性。例如，创建一个topic，值为NSQ。则key的生成规则如下：

```
topicName := "NSQ"
key := Registration{"topic", topicName, ""}
```

### 1.2.3 Producer
每一个Topic和Channel可能由多个生产者Producer发布，因此Producers存放是一个Producer指针数组。这些Producer都采用指针形式，因为一个Producer也可以发布多个Topic，因此利用指针的方式可以执行相同的Producer。

每个Producer代表一个生产者，存放该Producer的一些信息:

  - 上次更新时间.
  - 唯一id表示这个Producer
  - Producer远程地址
  - Producer主机名字
  - Producer广播地址
  - Producer的tcp端口，使得nsqlookupd可以和该Producer构建tcp通信
  - Producer的http 端口，也是用于和nsqlookupd交互使用
  - 版本，大概用来做版本兼容使用
 
其代码实现如下:

```
type Producer struct {
	peerInfo     *PeerInfo    // 存放Producer信息, 用一个指针指向其内存地址
	tombstoned   bool
	tombstonedAt time.Time
}

type PeerInfo struct {
	lastUpdate       int64                              // 上次更新时间
	id               string                             // 唯一id表示这个Producer
	RemoteAddress    string `json:"remote_address"`     // 远程地址
	Hostname         string `json:"hostname"`           // 主机名字
	BroadcastAddress string `json:"broadcast_address"`  // 广播地址， 和远程地址区别？？
	TCPPort          int    `json:"tcp_port"`           // tcp端口
	HTTPPort         int    `json:"http_port"`          // http 端口
	Version          string `json:"version"`            // 版本，大概用来做版本兼容使用
}
```

我们可以用一张图来表示这个注册表的结构：
![](/images/15190962370744.jpg)

topic t1的生产者是Producer1和Producer2, 数组中的Producer1和Producer2分别指向它们的内存地址。而每个Producer的信息存放在peerInfo中。

## 1.3 注册表的管理
定义了注册表结构后，如何管理注册表，进行topic和channel的增删呢。本质上使用的就是map的增、删、查操作, 无法是先构建Registration类型的key, 根据key去操作。因为这个注册表可能多个操作同时在并行执行，为了保住线程安全，每个涉及到RegistrationDB.registrationMap的增、删、查操作都利用了RegistrationDB定义的读写锁进行加锁，

### 1.3.1 创建Topic和channel
创建Topic和Chnnel是通过Http请求接口完成。**通过http创建一个topic或channel. 这时候没有将Producers信息存放进去而是初始化了一个Producers列表**。

```
key := Registration{"topic", topicName, ""}
// 里面实现真正的注册逻辑
s.ctx.nsqlookupd.DB.AddRegistration(key)
```

AddRegistration方法实现：

```
func (r *RegistrationDB) AddRegistration(k Registration) {
	r.Lock()
	defer r.Unlock() // 留在最后执行，不管是异常还是执行完成。类似java的finally
	// 是否已经创建了
	_, ok := r.registrationMap[k]
	if !ok {
		r.registrationMap[k] = Producers{}
	}
}
```

如果该key已经注册了，则直接返回，否则创建一个Producers列表，用Registration可以注册到而registrationMap中，后续添加Producer的工作则交给了AddProducer方法。这里需要重点说下channel的构建过程，channel注册的时候注册了两部分内容:

    1. 根据channel构建一个key，注册channel和Producers的映射
    2. 再根据channel对应的topic构建一个key, 注册topic和Producers的映射

具体代码如下：

```
s.ctx.nsqlookupd.logf(LOG_INFO, "DB: adding channel(%s) in topic(%s)", channelName, topicName)
key := Registration{"channel", topicName, channelName}
s.ctx.nsqlookupd.DB.AddRegistration(key)

s.ctx.nsqlookupd.logf(LOG_INFO, "DB: adding topic(%s)", topicName)
key = Registration{"topic", topicName, ""}
s.ctx.nsqlookupd.DB.AddRegistration(key)
```

### 1.3.2 注册
完成创建以后，各个producer通过tcp方式连接nsqlookupd,发送注册命令REGISTER完成注册。**nsqlookupd将当前机器注册到某个Topic或Channel中，这时候将时候将tcp连接的producer添加到对应的Producers中**。下面是tcp方式注册的主要逻辑，具体代码在nsqlookupd/lookup_protocl_v1.go的REGISTER函数中。

```
// 获取topci和channel
topic, channel, err := getTopicChan("REGISTER", params)
if err != nil {
	return nil, err
}

// 更新channel信息
if channel != "" {
	key := Registration{"channel", topic, channel}
	// 将Producer存放到列表中
	if p.ctx.nsqlookupd.DB.AddProducer(key, &Producer{peerInfo: client.peerInfo}) {
		p.ctx.nsqlookupd.logf(LOG_INFO, "DB: client(%s) REGISTER category:%s key:%s subkey:%s",
			client, "channel", topic, channel)
	}
}

// 更新topic信息
key := Registration{"topic", topic, ""}
// 将Producer信息添加到producers列表中
if p.ctx.nsqlookupd.DB.AddProducer(key, &Producer{peerInfo: client.peerInfo}) {
	p.ctx.nsqlookupd.logf(LOG_INFO, "DB: client(%s) REGISTER category:%s key:%s subkey:%s",
		client, "topic", topic, "")
}
```

p.ctx.nsqlookupd.DB.AddProducer方法负责将Producer添加到注册表中key对应的producers列表中，完成注册。

### 1.3.3 lookup
lookup是通过http请求的操作。消费者对特定的topic和channel感兴趣，因此消费者向nsqlookupd发起lookup操作，找到Channel对应的生产者Producers, 然后与这些Producers建立连接，订阅相关信息。这里看看lookup是如何实现的。

lookup操作是根据Topic查询该topic底下的所有channel，和对应的producers。所以包含三个步骤:
1. 根据Topic，看看是否已经注册了。如果没有注册抛出异常
2. 否者将topic下的所有channel获取出来
3. 获取该topic下的所有producers

代码参考http请求实现nsqlookupd/http.go的doLookup方法

```
func (s *httpServer) doLookup(w http.ResponseWriter, req *http.Request, ps httprouter.Params) (interface{}, error) {
	reqParams, err := http_api.NewReqParams(req)
	if err != nil {
		return nil, http_api.Err{400, "INVALID_REQUEST"}
	}
   // 获取topic值
	topicName, err := reqParams.Get("topic")
	if err != nil {
		return nil, http_api.Err{400, "MISSING_ARG_TOPIC"}
	}

  // 1. 根据Topic，看看是否已经注册了。如果没有注册抛出异常
	registration := s.ctx.nsqlookupd.DB.FindRegistrations("topic", topicName, "")
	if len(registration) == 0 {
		return nil, http_api.Err{404, "TOPIC_NOT_FOUND"}
	}

   // 2. 将topic下的所有channel获取出来。*表示取出所有
	channels := s.ctx.nsqlookupd.DB.FindRegistrations("channel", topicName, "*").SubKeys()
	
	// 3. 获取该topic下的所有producers
	producers := s.ctx.nsqlookupd.DB.FindProducers("topic", topicName, "")
	producers = producers.FilterByActive(s.ctx.nsqlookupd.opts.InactiveProducerTimeout,
		s.ctx.nsqlookupd.opts.TombstoneLifetime)
	return map[string]interface{}{
		"channels":  channels,
		"producers": producers.PeerInfo(),
	}, nil
}
```

### 1.3.4 注销
注销的工作就是从注册表指定的topic或channel中移除producer, 注销是使用tcp方式的UNREGISTER命令完成(因为tcp方式保持了客户端的信息)。

注销channel：
  1. 首先构建key
  2. 根据key去注册表中查询该key下的所有producers
  3. for循序遍历producers，如果producers的id与当前客户端的id一致，则移除
  
```
key := Registration{"channel", topic, channel}
// 移除生产者
removed, left := p.ctx.nsqlookupd.DB.RemoveProducer(key, client.peerInfo.id)
if removed {
	p.ctx.nsqlookupd.logf(LOG_INFO, "DB: client(%s) UNREGISTER category:%s key:%s subkey:%s",
		client, "channel", topic, channel)
}


// remove a producer from a registration
func (r *RegistrationDB) RemoveProducer(k Registration, id string) (bool, int) {
	r.Lock()
	defer r.Unlock()
	// 获取全部
	producers, ok := r.registrationMap[k]
	if !ok {
		return false, 0
	}
	removed := false
	cleaned := Producers{}
	// 效率不高
	for _, producer := range producers {
		if producer.peerInfo.id != id {
			cleaned = append(cleaned, producer)
		} else {
			removed = true
		}
	}
	// Note: this leaves keys in the DB even if they have empty lists
	r.registrationMap[k] = cleaned  // 存放一个空对象
	return removed, len(cleaned)
}
```



注销topic逻辑类似，需要扫描topic下的所有channel并注销，最后注销topic下的producer.

### 1.3.5 删除
channel的删除是根据topic, channel查询出所有的已经注册的registrations, 然后根据这些key从registryMap中删除。

```
// 查找
registrations := s.ctx.nsqlookupd.DB.FindRegistrations("channel", topicName, channelName)
if len(registrations) == 0 {
	return nil, http_api.Err{404, "CHANNEL_NOT_FOUND"}
}

s.ctx.nsqlookupd.logf(LOG_INFO, "DB: removing channel(%s) from topic(%s)", channelName, topicName)
for _, registration := range registrations {
   // 删除
	s.ctx.nsqlookupd.DB.RemoveRegistration(registration)
}
```

RemoveRegistration方法底层实现是采用了golang的map的delete方法, 为了保住数据一致性，操作时进行加锁。

```
func (r *RegistrationDB) RemoveRegistration(k Registration) {
	r.Lock()
	defer r.Unlock()
	delete(r.registrationMap, k)
}
```

topic底下有多个channel，所有topic的删除首先需要删除channel，然后再删除topic:

```
// 先查找所有的channel注册并删除
registrations := s.ctx.nsqlookupd.DB.FindRegistrations("channel", topicName, "*")
for _, registration := range registrations {
	s.ctx.nsqlookupd.logf(LOG_INFO, "DB: removing channel(%s) from topic(%s)", registration.SubKey, topicName)
	s.ctx.nsqlookupd.DB.RemoveRegistration(registration)
}

// 查询topic，并删除
registrations = s.ctx.nsqlookupd.DB.FindRegistrations("topic", topicName, "")
for _, registration := range registrations {
	s.ctx.nsqlookupd.logf(LOG_INFO, "DB: removing topic(%s)", topicName)
	s.ctx.nsqlookupd.DB.RemoveRegistration(registration)
}
```

# 二. 运行过程及源码实现
上面介绍了nsqlookupd的设计原理，相信大家对nsqlookupd的整体架构和实现机制有了大致了解。为了进一步理解nsqlookupd整个运行过程和源码实现机制。这部分通过阅读代码了解核心环节的实现过程。

## 2.1 启动
### 2.1.1 go-svc
首先了解nsqlookupd是如何启动的，以及在启动过程中都做了些什么工作。NSQ中两个后台进程nsqd、nsqlookup都是采用go-svc包控制进程初始化、启动和关闭。go-svc是一个开源组件：

```
// 代码
github.com/judwhite/go-svc/svc
// wiki
https://godoc.org/golang.org/x/sys/windows/svc
```

svc采用了模板设计模式在负责初始化、启动、关闭进程。 这些初始化Init、启动Start和关闭Stop方法通过接口定义，交给具体进程去实现。而svc则负责管理何时去调用这些方法。我们看看svc的核心代码:

```
// Service接口，定义了Init、Start、Stop接口。
// 这里传入接口的具体实现
func Run(service Service, sig ...os.Signal) error {
	env := environment{}
	
	// 初始化
	if err := service.Init(env); err != nil {
		return err
	}

   // 启动
	if err := service.Start(); err != nil {
		return err
	}

	if len(sig) == 0 {
		sig = []os.Signal{syscall.SIGINT, syscall.SIGTERM}
	}
    
  // 构建信号链，并睡眠等待，利用信号方式进行终止. 
	signalChan := make(chan os.Signal, 1)
	signalNotify(signalChan, sig...)
	<-signalChan

	return service.Stop()
}
```

svc采用了信号方式关闭程序，信号是IPC方式中唯一一种异步通信方式。利用信号方式最大的好处就是程序在收到内核关闭和信号时，可以在关闭进程时做一些扫尾工作，例如内存数据保持等。

### 2.1.2 program对象
apps/nsqlookupd/nsqlookupd.go是nsqlookup dmain方法入口，代码中定义了program结构，其实现了svc的Service接口。因此可以交给svc来负责管理program的初始化、启动和关闭动作。上文说到NSQLookupd是整个服务的核心，完成各个服务的管理工作。因此program结构中存放了一个指向NSQLookupd的指针，在启动的时候对其进行初始化:

```
type program struct {
	nsqlookupd *nsqlookupd.NSQLookupd // nsqlookupd 服务实例
} 
```

接下来看看nsqlookupd的main方法，方法中首先创建一个program对象，此刻nsqlookupd指针值时nil. program实现了svc的三个方法，因此可以交给svc进行管理：

```
func main() {
	// 构建一个实例
	prg := &program{}
	// svc 框架的Run 方法启动一个service
	if err := svc.Run(prg, syscall.SIGINT, syscall.SIGTERM); err != nil {
		log.Fatal(err)
	}
}
```

program实例的启动逻辑在Start方法，该方法完成以下工作:
  1. 命令行参数解析
  2. 如果查询版本指令"version", 则返回当前版本并退出
  3. 解析配置文件参数
  4. 将配置文件参数和命令行参数进行合并
  5. 创建一个NSQLookupd实例
  6. 执行NSQLookupd实例的Main方法
  7. 最后保持到program的nsqlookupd 指针中

具体代码如下：
  
```
// 实现了svc的Start方法，完成启动流程
func (p *program) Start() error {
	// 初始化nsqlookup配置
	opts := nsqlookupd.NewOptions()

	// 解析用户flag传参
	flagSet := nsqlookupdFlagSet(opts)
	flagSet.Parse(os.Args[1:])

	// 输出版本并退出, 表示是为了查询当前版本指令
	if flagSet.Lookup("version").Value.(flag.Getter).Get().(bool) {
		fmt.Println(version.String("nsqlookupd"))
		os.Exit(0)
	}

	// 解析配置文件参数
	var cfg map[string]interface{}
	configFile := flagSet.Lookup("config").Value.String()
	if configFile != "" {
		// 如果配置文件不为空，则解析。并存放到cfg中
		_, err := toml.DecodeFile(configFile, &cfg)
		if err != nil {
			log.Fatalf("ERROR: failed to load config file %s - %s", configFile, err.Error())
		}
	}

	// 将用户传入的参数和配置文件参数合并，并实例化NSQLookupd对象
	options.Resolve(opts, flagSet, cfg)
	daemon := nsqlookupd.New(opts)

	// 运行nsqlookup守护进程， 执行nsqlookup实例的Main方法
	daemon.Main()
	// 保持到结构体对象中
	p.nsqlookupd = daemon
	return nil
}
```

### 2.1.3 nsqlookupd模块之Main函数
nsqlookupd是整个服务的核心，其结构以及在上文提到。nsqlookupd的代码在nsqlookupd/nsqlookupd.go中。而nsqlookupd的服务启动方法则在nsqlookupd模块的Main函数中，其主要完成以下几个工作：
 
  1. 注册tcpListener监听器, 并启动tcp服务，该服务是一个goroutine进程。
  
  ```
  // 注册tcp服务监听器， 采用go内置模块net。
	tcpListener, err := net.Listen("tcp", l.opts.TCPAddress)
	...
	// tcp服务实例
	tcpServer := &tcpServer{ctx: ctx}

	// 封装的waitGroup，内部使用goroutine启动该服务，使用waitGroup守护改协程直到退出.
	// 启动服务后可以接受其他模块的tcp请求
	l.waitGroup.Wrap(func() {
		protocol.TCPServer(tcpListener, tcpServer, l.logf)
	})
  ```
  2. 同样注册一个httpListener监听器，并启动newHTTPServer服务(创建了一个goroutine进程)
  
  ```
  // 注册http的监听器
	httpListener, err := net.Listen("tcp", l.opts.HTTPAddress)
	...
	// 创建http服务实例
	httpServer := newHTTPServer(ctx)
	// 启动http服务，启动服务后可以接受其他模块的http请求
	l.waitGroup.Wrap(func() {
		http_api.Serve(httpListener, httpServer, "HTTP", l.logf)
	})
  ```
  
  这时候便完成了nsqlookupd的服务。下面分析http和tcp服务是如何实现的
  
## 2.2 tcp
internal/protocol/tcp_server.go 是tcpServer的具体实现，核心代码如下：

```
// 轮询
for {
	// 接收client连接并回调handle方法
	clientConn, err := listener.Accept()
	if err != nil {
	    ... // 异常处理代码
		 break
	}
	// 这里的handle方法虽然是TCPHandler的接口类型，实际回调的是nsqlookupd/tcp.go中Handle方法
	go handler.Handle(clientConn)
}
```

利用轮询的方式不断去监听:

 1. 如果listener监听到客户端的连接请求以后，将该请求交给TCPHandler处理
 2. 如果连接中收到异常，则退出轮询，停止TCP服务。

### 2.2.1 请求处理
根据TCPHandler根据tcp消息数据的protocolMagic选择处理方式，目前protocolMagic只有“ V1”. 根据V1版本的TCP协议，每一行都是一个命令，因此先解析命令根据命令处理。如上文所说，处命令有四种:
 
 - PING: 心跳检测，nsqd每隔一段时间都会向nsqlookupd发送心跳
 - IDENTIFY: 身份识别, 当nsqd第一次连接nsqlookupd时，发送IDENTITY验证自己身份
 - REGISTER: 注册topic和channel, **这里会将客户端的信息设置到注册表中**.
 - UNREGISTER: 撤销topic或channel.

 代码如下：
 ```
 func (p *LookupProtocolV1) Exec(client *ClientV1, reader *bufio.Reader, params []string) ([]byte, error) {
	switch params[0] {
	case "PING":
		// ping，心跳检测，nsqd每隔一段时间都会向nsqlookupd发送心跳
		return p.PING(client, params)
	case "IDENTIFY":
		// 身份识别, 当nsqd第一次连接nsqlookupd时，发送IDENTITY验证自己身份
		return p.IDENTIFY(client, reader, params[1:])
	case "REGISTER":
		// 注册
		return p.REGISTER(client, reader, params[1:])
	case "UNREGISTER":
		// 注销
		return p.UNREGISTER(client, reader, params[1:])
	}
	return nil, protocol.NewFatalClientErr(nil, "E_INVALID", fmt.Sprintf("invalid command %s", params[0]))
}
 ```
 
 REGISTER和UNREGISTER命令上文已经结束，因此忽略。其他读者可以参考具体代码去理解。
 
## 2.3 http
http 启动有三步：

  1. 注册http的监听器
  2. 创建http服务实例
  3. 启动http服务

```
  // 注册http的监听器
	httpListener, err := net.Listen("tcp", l.opts.HTTPAddress)
	...
	// 创建http服务实例
	httpServer := newHTTPServer(ctx)
	// 启动http服务，启动服务后可以接受其他模块的http请求
	l.waitGroup.Wrap(func() {
		http_api.Serve(httpListener, httpServer, "HTTP", l.logf)
	})
  ```
  
这里主要看看第二步创建http服务实例，创建过程在nsqlookupd/http.go文件中：

```
func newHTTPServer(ctx *Context) *httpServer {
	log := http_api.Log(ctx.nsqlookupd.opts.Logger)
	//实例化一个httprouter
	router := httprouter.New()
	router.HandleMethodNotAllowed = true
	//设置panic时的处理函数
	router.PanicHandler = http_api.LogPanicHandler(ctx.nsqlookupd.opts.Logger)
	//设置not found处理函数
	router.NotFound = http_api.LogNotFoundHandler(ctx.nsqlookupd.opts.Logger)
	//当请求方法不支持时的处理函数
	router.MethodNotAllowed = http_api.LogMethodNotAllowedHandler(ctx.nsqlookupd.opts.Logger)
	s := &httpServer{
		ctx:    ctx,
		router: router,
	}
	router.Handle("GET", "/ping", http_api.Decorate(s.pingHandler, log, http_api.PlainText))
	//省略后续路由定义
	...
}

```

nsqlookupd的http服务路由使用的是开源框架httprouter；httprouter路由使用radix树来存储路由信息，路由查找上效率高，同时提供一些其他优秀特性，因此很受欢迎，gin web框架使用的就是httprouter路由；在这个函数中定义了每个接口，以及这个接口对应处理函数。

```
...
router.Handle("POST", "/topic/create", http_api.Decorate(s.doCreateTopic, log, http_api.V1))
	router.Handle("POST", "/topic/delete", http_api.Decorate(s.doDeleteTopic, log, http_api.V1))
	router.Handle("POST", "/channel/create", http_api.Decorate(s.doCreateChannel, log, http_api.V1))
	router.Handle("POST", "/channel/delete", http_api.Decorate(s.doDeleteChannel, log, http_api.V1))
...
```

在http中大量使用了装饰器模式，对每个请求方法都包装了一些装饰。首先我们看看这个装饰器http_api.Decorate函数，在文件internal/http_api/api_response.go：

```
func Decorate(f APIHandler, ds ...Decorator) httprouter.Handle {
	decorated := f
	for _, decorate := range ds {
		decorated = decorate(decorated)
	}
	return func(w http.ResponseWriter, req *http.Request, ps httprouter.Params) {
		decorated(w, req, ps)
	}
}
```

这个函数其实就是一个装饰器，第一个参数f APIHandler为需要被装饰的视图函数，从第二参数开始，都是装饰函数ds ...Decorator，最后返回装饰好的视图函数；


# 总结
1. nsqlookupd中提供了两种通信方式http和tcp.
2. nsqlookupd主要是做注册中心，管理Topic/Channel与Producer(nsqd)之间的关系。为了管理便于管理使用了map形式，key是Registration，value是Producers指针列表。
3.  为了保住注册表的线程安全，采用了读写锁。注册表的增删查改底层采用map的操作。
4. NSQlookupd模块是整个nsqlookupd的核心
4. nsqlookupd利用so-svc框架完成启动过程。NSQlookupd的Main方法完成了http和tcp服务的启动。
5. TCP采用轮询方式监听客户端行为，根据nsqlookupd的tcp协议格式,解析命令行，根据不同命令做想要处理。V1版本的命令一共有四种：PING、IDENTIFY、REGISTER、UNREGISTER。
6. nsqlookupd的http服务路由使用的是开源框架httprouter；
7. nsqlookupd使用了**装饰模式、模板模式**等。

# 参考
 - [nsq tcp协议规范](http://wiki.jikexueyuan.com/project/nsq-guide/tcp_protocol_spec.html)
 - [nsq源码分析（2）：nsqlookup之tcp服务](http://blog.csdn.net/shanhuhai5739/article/details/72900964)
 - [NSQ源码分析之nsqlookupd](http://luodw.cc/2016/12/13/nsqlookupd/)
 



