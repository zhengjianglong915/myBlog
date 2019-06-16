title: NSQ源码解析(1)--设计理念浅析
layout: post
date: 2018-02-18 12:17:32
comments: true
categories: NSQ源码解析
tags: 
    - 源码解析
    - NSQ
    - golang
    - 消息队列
    
keywords: “NSQ”, "缓存机制"
description:  Nsq是一个消息队列,具有高可用性、无单点故障、和低延迟、可靠性的消息传递等特性。本文主要是介绍NSQ的设计理念以及与其他消息队列的对比。

---

# 一. 背景
最近刚学习了go语言，觉得太还好用了。很多用法和python一样，通过灵活的、简单的方式为开发人员节省大量的开发时间，易于使用。而其不像python，不是一门面向对象语言，用法更加接近C。具有结构、指针的特点。可以说是C的一个灵活和易用性版本。

同时最近也在看消息队列相关的东西，前几天看了kafka的内容，虽然目前kafka已经是消息队列的明星，在大数据时代更受追捧。但由于其实现语言是scala, 若想深入学习则需要学习scala。鉴于以上原因选择NSQ消息队列，一方面了解NSQ消息队列的内部机制，另一方面通过NSQ源码加深对go语言的理解和掌握。从中学习go语言的一些优秀特性。

# 二. NSQ
## 2.1 概念
Nsq是一个消息队列，最初为提供短链接服务的应用Bitly而开发。它一个采用去中心化的拓扑结构的分布式实时消息平台。NSQ框架具有高可用性、无单点故障、和低延迟、可靠性的消息传递等特性。它基于Go语言开发，能够为高吞吐量的网络服务器带来性能的优化，稳定性和鲁棒性。

NSQ是一个**简单**的队列，基本核心就是**简单性**，这意味着它很容易进行故障推理和很容易发现bug。消费者可以自行处理故障事件而不会影响系统剩下的其余部分。根据[官网](http://nsq.io/overview/features_and_guarantees.html)的介绍, NSQ具有以下几个主要特点:

 - 具有分布式且无单点故障(SPOF)的拓扑结构 
 - 支持水平扩展，在无中断情况下能够无缝地添加集群节点
 - 低延迟的消息推送，参见[官方性能文档](http://nsq.io/overview/performance.html)
 - 具有组合式的负载均衡和多播形式的消息路由
 - 既擅长处理面向流（高吞吐量）的工作负载，也擅长处理面向Job的（低吞吐量）工作负载
 - 消息数据既可以存储于内存中，也可以存储在磁盘中
 - 实现了生产者、消费者自动发现和消费者自动连接生产者，参见nsqlookupd
 - 支持安全传输层协议（TLS），从而确保了消息传递的安全性
 - 具有与数据格式无关的消息结构，支持JSON、Protocol Buffers、MsgPacek等消息格式
 - 非常易于部署（几乎没有依赖）和配置（所有参数都可以通过命令行进行配置）
 - 使用了简单的TCP协议且具有多种语言的客户端功能库
 - 具有用于信息统计、管理员操作和实现生产者等的HTTP接口
 - 为实时检测集成了统计数据收集器StatsD
 - 具有强大的集群管理界面，参见nsqadmin

## 2.2 术语
**Topic**: 一个可供订阅的话题，是消息的分类概念。
**channel**: 一个通道（channel）是消费者订阅了某个话题的逻辑分组. 一个Topic有可以分为多个Channel，每当一个发布者发送一条消息到一个topic，消息会被复制到所有消费者连接的channel上，从而实现多播分发，而channel上的每个消息被分发给它的订阅者，从而实现负载均衡。实际上，在消费者第一次订阅时就会创建channel。Channel会将消息进行排列，如果没有消费者读取消息，消息首先会在内存中排队，当量太大时就会被保存到磁盘中。



# 三. 设计与实现
## 3.1 整体架构

NSQ主要有三个后台进程组成：

 - nsqd：一个负责接收、排队、转发消息到客户端的守护进程
 - nsqlookupd：管理拓扑信息并提供最终一致性的发现服务的守护进程
 - nsqadmin：一套Web用户界面，可实时查看集群的统计数据和执行各种各样的管理任务
 
另外还有一个非常重要的组件，utilities。utilities是常见基础功能、数据流处理工具，如nsq_stat、nsq_tail、nsq_to_file、nsq_to_http、nsq_to_nsq、to_nsq等。

### 3.1.1 nsqd
一个负责接收、排队、转发消息到客户端的守护进程。是NSQ的核心部分，它主要负责message的收发，队列的维护。nsqd会默认监听一个tcp端口(4150)和一个http端口(4151)以及一个可选的https端口。当一个nsqd节点启动时，它向一组nsqlookupd节点进行注册操作，并将保存在此节点上的topic和channel进行广播。

客户端可以发布消息到nsqd守护进程上，或者从nsqd守护进程上读取消息。通常，消息发布者会向一个单一的local nsqd发布消息，消费者从连接了的一组nsqd节点的topic上远程读取消息。

总的来说，nsqd 具有以下功能或特性：

 - 对订阅了同一个topic，同一个channel的消费者使用负载均衡策略（不是轮询）
 - 只要channel存在，即使没有该channel的消费者，也会将生产者的message缓存到队列中（注意消息的过期处理）
 - 保证队列中的message至少会被消费一次，即使nsqd退出，也会将队列中的消息暂存磁盘上(结束进程等意外情况除外)
 - 限定内存占用，能够配置nsqd中每个channel队列在内存中缓存的message数量，一旦超出，message将被缓存到磁盘中
 - topic，channel一旦建立，将会一直存在，要及时在管理台或者用代码清除无效的topic和channel，避免资源的浪费

![nsqd](/images/nsqd.gif)

从上图可以看出，单个nsqd可以有多个Topic，每个Topic又可以有多个Channel。Channel能够接收Topic所有消息的副本，从而实现了消息多播分发；而Channel上的每个消息被分发给它的订阅者，从而实现负载均衡，所有这些就组成了一个可以表示各种简单和复杂拓扑结构的强大框架。

### 3.1.2 nsqlookupd
nsqlookupd是守护进程负责管理拓扑信息。客户端通过查询 nsqlookupd 来发现指定话题（topic）的生产者，并且 nsqd 节点广播话题（topic）和通道（channel）信息。

简单的说nsqlookupd就是中心管理服务，它使用tcp(默认端口4160)管理nsqd服务，使用http(默认端口4161)管理nsqadmin服务。同时为客户端提供查询功能

总的来说，nsqlookupd具有以下功能或特性：

 - 唯一性，在一个Nsq服务中只有一个nsqlookupd服务。当然也可以在集群中部署多个 nsqlookupd，但它们之间是没有关联的
 - 去中心化，即使nsqlookupd崩溃，也会不影响正在运行的nsqd服务
 - 充当nsqd和naqadmin信息交互的中间件
 - 提供一个http查询服务，给客户端定时更新nsqd的地址目录 

### 3.1.3 nsqadmin
是一套 WEB UI，用来汇集集群的实时统计，并执行不同的管理任务。nsqadmin具有以下功能或特性：

 - 提供一个对topic和channel统一管理的操作界面以及各种实时监控数据的展示，界面设计的很简洁，操作也很简单
 - 展示所有message的数量
 - 能够在后台创建topic和channel
 - nsqadmin的所有功能都必须依赖于nsqlookupd，nsqadmin只是向nsqlookupd传递用户操作并展示来自nsqlookupd的数据

## 3.2 拓扑结构
nsqlookupd，nsqd与客户端中消费者和生产者如何进行交互、沟通的呢？

### 生产者
生产者必须直连nsqd去投递message，但是该方式存在一个问题:如果生产者所连接的nsqd宕机了，那么message就会投递失败，所以在客户端必须自己实现相应的备用方案。NSQ推荐通过他们相应的nsqd实例使用**协同定位发布者**，这意味着即使面对网络分区，消息也会被保存在本地，直到它们被一个消费者读取。更重要的是，发布者不必去发现其他的nsqd节点，他们总是可以向本地实例发布消息。

### 消费者
消费者有两种方式与nsqd建立连接:

 - 消费者直连nsqd，这是最简单的方式，缺点是nsqd服务无法实现动态伸缩了.
 - 消费者通过http查询nsqlookupd获取该nsqlookupd上所有nsqd的连接地址，然后再分别和这些nsqd建立连接(官方推荐的做法).
 
![consumer_relation](/images/consumer_relation.png)

### 消息的生命周期
让我们观察一个关于nsq如何在实际中工作的。

![](/images/15190292062276.jpg)

1. 首先，一个发布者向它的本地nsqd发送消息，要做到这点，首先要先打开一个连接，然后发送一个包含topic和消息主体的发布命令
2. 事件topic会复制这些消息并且在每一个连接topic的channel上进行排队。有三个channel，它们其中之一作为档案channel。每个channel的消息都会进行排队，直到一个worker把他们消费，如果此队列超出了内存限制，消息将会被写入到磁盘中。
3. Nsqd节点首先会向nsqlookup广播他们的位置信息，一旦它们注册成功，worker将会从nsqlookup服务器节点上发现所有包含事件topic的nsqd节点。
4. 然后每个worker向每个nsqd主机进行订阅操作，用于表明worker已经准备好接受消息了。



## 3.3 设计细节

在设计的时候为了考虑合理的权衡，NSQ有以下特点：

 - 支持消息内存队列的大小设置，默认完全持久化（值为0），消息即可持久到磁盘也可以保存在内存中。
 - 保证消息至少传递一次,以确保消息可以最终成功发送。 kafka则提供了三种事务选择。
 - 收到的消息是无序的, 实现了松散订购. kafka保证了消息有序性
 - 发现服务nsqlookupd具有最终一致性,消息最终能够找到所有Topic生产者
 - 没有复制 ——不像其他的队列组件，NSQ并没有提供任何形式的复制和集群，也正是这点让它能够如此简单地运行，但它确实对于一些高保证性高可靠性的消息发布没有足够的保证。
 - 没有严格的顺序 ——虽然Kafka由一个有序的日志构成，但NSQ不是。消息可以在任何时间以任何顺序进入队列。

### 消息传递担保
NSQ保证消息将交付至少一次，虽然消息可能是重复的。这个担保是作为协议和工作流的一部分，工作原理如下：

 - 客户表示已经准备好接收消息
 - NSQ 发送一条消息，并暂时将数据存储在本地（在 re-queue 或 timeout）
 - 客户端回复 FIN（结束）或 REQ（重新排队）分别指示成功或失败。如果客户端没有回复, NSQ 会在设定的时间超时，自动重新排队消息。

 这确保了消息丢失唯一可能的情况是不正常结束 nsqd 进程，在内存中的任何信息（或任何缓冲未刷新到磁盘）都将丢失。一种解决方案是构成冗余 nsqd对（在不同的主机上）接收消息的相同部分的副本。
 
### Topic 和Channel
一个Topic（话题）对应多个Channel(通道)每个通道都接收到一个话题中所有消息的拷贝。Topic和Chanel都不是预先配置的，话题由第一次发布消息到命名的Topic或第一次通过订阅一个命名Topic来创建。Channel被第一次订阅到指定的通道创建。

一个通道一般会有多个客户端连接。假设所有已连接的客户端处于准备接收消息的状态，每个消息将被传递到一个随机的客户端.

### 消除单点故障
NSQ采用push的方式将消息数据推送到客户端，而不是像Kafka一样等待客户端的拉取，这样实现的好处就是**最大限度地提高性能和吞吐量**的。这个概念，称之为**RDY**状态，基本上是客户端流量控制的一种形式。

客户端的消息消费进度由NSQ来控制，通过RDY状态记录客户端消息读取进度：

 - 当客户端连接到 nsqd 和并订阅到一个通道时，它被放置在一个 RDY 为 0 状态(未发送信息)。
 - 当客户端已准备好接收消息发送，更新它的命令RDY状态到它准备处理的数量，比如100。当 100 条消息可用时，将被传递到客户端。
 - 服务器端为那个客户端每次递减 RDY 计数。

### 心跳和超时
NSQ采用push方式将消息传递给消费者，因此需要保证客户端在线。NSQ通过心跳机制和超时检查观察客户端情况，每隔一段时间，nsqd将想消费者发送一个心跳线连接。当检测到一个致命错误，客户端连接被强制关闭。在传输中的消息会超时而重新排队等待传递到另一个消费者。最后，错误会被记录并累计到各种内部指标。


# 和其他消息队列对比
## 设计对比
### RabbitMQ
RabbitMQ是使用Erlang编写的一个开源的消息队列，本身支持很多的协议：AMQP，XMPP, SMTP, STOMP，也正因如此，它非常**重量级**，更适合于企业级的开发。同时实现了Broker构架，这意味着消息在发送给客户端时先在中心队列排队。对路由，负载均衡或者数据持久化都有很好的支持。

### Redis
Redis是一个基于Key-Value对的NoSQL数据库，开发维护很活跃。虽然它是一个Key-Value数据库存储系统，但它本身支持MQ功能，所以完全可以当做一个**轻量级**的队列服务来使用。对于RabbitMQ和Redis的入队和出队操作，各执行100万次，每10万次记录一次执行时间。测试数据分为128Bytes、512Bytes、1K和10K四个不同大小的数据。实验表明：入队时，当数据比较小时Redis的性能要高于RabbitMQ，而如果数据大小超过了10K，Redis则慢的无法忍受；出队时，无论数据大小，Redis都表现出非常好的性能，而RabbitMQ的出队性能则远低于Redis。

### ZeroMQ
ZeroMQ号称最快的消息队列系统，尤其针对大吞吐量的需求场景。ZMQ能够实现RabbitMQ不擅长的高级/复杂的队列，但是开发人员需要自己组合多种技术框架，技术上的复杂度是对这MQ能够应用成功的挑战。ZeroMQ具有一个独特的非中间件的模式，你不需要安装和运行一个消息服务器或中间件，因为你的应用程序将扮演了这个服务角色。你只需要简单的引用ZeroMQ程序库，可以使用NuGet安装，然后你就可以愉快的在应用程序之间发送消息了。但是ZeroMQ仅提供非持久性的队列，也就是说如果宕机，数据将会丢失。其中，Twitter的Storm 0.9.0以前的版本中默认使用ZeroMQ作为数据流的传输（Storm从0.9版本开始同时支持ZeroMQ和Netty作为传输模块）。

### ActiveMQ
ActiveMQ是Apache下的一个子项目。 类似于ZeroMQ，它能够以代理人和点对点的技术实现队列。同时类似于RabbitMQ，它少量代码就可以高效地实现高级应用场景。

### Kafka/Jafka
Kafka是Apache下的一个子项目，是一个高性能跨语言分布式发布/订阅消息队列系统，而Jafka是在Kafka之上孵化而来的，即Kafka的一个升级版。具有以下特性：

- 快速持久化，可以在O(1)的系统开销下进行消息持久化；
- 高吞吐，在一台普通的服务器上既可以达到10W/s的吞吐速率；
- 完全的分布式系统，Broker、Producer、Consumer都原生自动支持分布式，自动实现负载均衡；
- 支持Hadoop数据并行加载，对于像Hadoop的一样的日志数据和离线分析系统，但又要求实时处理的限制，这是一个可行的解决方案。Kafka通过Hadoop的并行加载机制来统一了在线和离线的消息处理。
- Apache Kafka相对于ActiveMQ是一个非常轻量级的消息系统，除了性能非常好之外，还是一个工作良好的分布式系统。
- 保证消息的顺序性
- 同时是一个存储系统，数据被消费消费后没有立即删除，而是存储在磁盘上
- 采用Push和 Pull方式发布和拉取消息

### 性能对比
性能对比 待补充

![](/images/15190082760217.jpg)

# 源码目录结构
为了便于阅读源码，首先对NSQ的代码目录结构做个简单介绍，这样对于整个源码结构有一个清晰的认识。核心代码都放在apps下，所以我们在阅读源码的时候重点关注这个目录下面的: nsqd、nsqlookup、nsqadmin等。

```
nsq
├── apps # 所有组件的main入口，包括了nsqd, nsqlookupd, nsqadmin和一些工具
│   ├── nsq_pubsub
│   ├── nsq_stat
│   ├── nsq_tail
│   ├── nsq_to_file
│   ├── nsq_to_http
│   ├── nsq_to_nsq
│   ├── nsqadmin      # nsqadmin组件入口
│   ├── nsqd          # nsqd组件入口
│   ├── nsqlookupd    # nsqlookup组件入口
│   └── to_nsq
├── bench               # 批量测试工具
│   ├── bench.py
│   ├── bench_channels  # 
│   ├── bench_reader    # 消息的消费者
│   ├── bench_writer    # 消息的生产者
├── contrib
│   ├── nsq.spec               # 可根据该文件生成nsq的rpm包
│   ├── nsqadmin.cfg.example   # nsqadmin配置文件举例
│   ├── nsqd.cfg.example       # nsqd配置文件举例
│   └── nsqlookupd.cfg.example # nsqlookup配置文件举例
├── internal        # nsq的基础库，存放了NSQ内部使用的一些函数，例如三大组件通用函数
|   ├── clusterinfo # 集群相关
├── nsqadmin        # web组件，nsqadmin源码
├── nsqd            # 消息处理组件，目录存放了关于nsqd源码
├── nsqlookupd      # 管理nsqd拓扑信息组件，nsqlookupd的源码；
```

# 总结

- 生产者必须和nsqd部署在一个机器上？
- 重新排队是做什么？


# 参考
- [深入NSQ 之旅 ](https://www.oschina.net/translate/day-22-a-journey-into-nsq)
- [Community Contributed Go Articles and Tutorials](https://blog.gopheracademy.com/advent-2013/day-22-a-journey-into-nsq/)
- [NSQ：分布式的实时消息平台](http://www.infoq.com/cn/news/2015/02/nsq-distributed-message-platform/) 
- [golang使用Nsq](https://segmentfault.com/a/1190000009194607) | 如何用golang使用NSQ
- [NSQ理解](https://www.cnblogs.com/zhangboyu/p/7452759.html)
- [消息中间件NSQ深入与实践](https://mp.weixin.qq.com/s/lrbIx88Z1HwWNTO_5aABJQ)


