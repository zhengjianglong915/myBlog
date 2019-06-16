title: Kafka源码解析(2)--分布式下的高可用性
layout: post
date: 2018-04-15 20:17:32
comments: true
categories: Kafka源码解析
tags: 
    - 源码解析
    - Kafka
    
keywords: “Kafka”, "源码学习"
description: Kafka具有分布性，使得Kafka具有良好的拓展能力和容错能力、高可用性。为了避免一个或几个broker宕机，其上所有的Partition数据都不可被消费，而导致部分服务不可用。Kafka为每个partition设置多个replication, 均衡分布在集群中的多个broker中。即使一个或几个broker不可工作时，其他broker因为存储partition数据副本，所以整个集群可以正常工作。

---

# 一. 术语
**broker**： Kafka集群中的一个节点，可以看做是一个Kafka服务。也负责了Kafka的消息存储。
**partition**: Topic物理上的分组，一个topic可以分为多个partition，每个partition是一个有序的队列。是实现分布式高可用的基础。

# 二. 分布式设计
## 2.1 如何保证高可用性
Kafka具有分布性，使得Kafka具有良好的拓展能力和容错能力、高可用性。为了避免一个或几个broker宕机，其上所有的Partition数据都不可被消费，而导致部分服务不可用。Kafka为每个partition设置多个replication, 均衡分布在集群中的多个broker中。即使一个或几个broker不可工作时，其他broker因为存储partition数据副本，所以整个集群可以正常工作。


## 2.2 如何管理集群节点
在整个集群中如何知道新的broker加入和broker的退出？如何管理这些broker?当集群中有1个新的broker加入，或者某个旧的broker死亡，集群中其它机器都需要知道这件事.可以通过监听Zookeeper上面的/broker/ids结点，其每个子结点就对应1台broker机器，当broker机器添加，子结点列表增大；broker机器死亡，子结点列表节点减小。

**为了减小Zookeeper的压力，同时也降低整个分布式系统的复杂度，Kafka引入了一个“中央控制器“，也就是Controller**。
 
其基本思路是：先通过Zookeeper在所有broker中选举出一个Controller，然后用这个Controller来控制其它所有的broker，而不是让zookeeper直接控制所有的机器。 

比如上面对/broker/ids的监听，并不是所有broker都监听此结点，而是只有Controller监听此结点，这样就把一个**“分布式“问题转化成了“集中式“问题**，即降低了Zookeeper负担，也便于控制逻辑的编写。

## 2.3 如何同步Partition多份数据

在kafka中每一个partition会分布在集群中多个partition中，如何保证这些数据同步呢？kafk在用一主多从的设计思路，在partition所有的broker中选举一个broker作为leader，而partition上的其他broker作为Follower. leader具有读写权限，Producer和Consumer只与这个Leader交互，其它Replica作为Follower从Leader中复制数据。

Follower和消费者一样从Leader中订阅消息，将消息进行备份。如果Leader的消息被某个Follower完全同步则将该Follower加入到ISR(同步副本集)中。如果Follower在10秒以内没有同步成功，则被移除ISR。 ISR是主副本的一个完全同步副本集，这个列表中的副本都已经完全同步了消息。如果Leader发生了宕机，则可以直接从ISR中获取一个副本作为Leader而不担心数据丢失。

 为什么要这么设计呢？如果没有leader，那么每个broker都具有读写权限，为了保持每个broker上的Partition数据一致性，每个broker之间比如要相互通信，同步各自broker上最新的partition数据。这种两两通信交互负责性很高，形成了N*N的通信连接。数据的一致性和有序性非常难保证，大大增加了Replication实现的复杂性，同时也增加了出现异常的几率。而引入Leader后，只有Leader负责数据读写，Follower只向Leader顺序Fetch数据（N条通路），系统更加简单且高效。
 
 Replica 设计的目标有：
 
  - 使Partition Replica能够均匀地分配至各个Kafka Broker（负载均衡）；
  - 如果Partition的第一个Replica分配至某一个Kafka Broker，那么这个Partition的其它Replica则需要分配至其它的Kafka Brokers，即Partition Replica分配至不同的Broker；
  - 提升系统容错性。如果leader宕机了，则副本可以直接启动作为Leader.

## 2.3 分布式整体架构

以下是kafka分布式大致的架构图：

 ![](/images/15189454567278.jpg)


该图包含以下几点信息:

 1. Kafka中的所有组成单元 Producer、Broker、Consumer在启动时都会向Zookeeper注册。
 1. kafka在**所有的broker中选出了broker作为Controller**，用来管理集群节点。Controller会与集群中的每个broker建立连接，包括它自己（因为其本身也是一个broker）。如图有3个broker,建立了三条橙色的连接线。
 2. 为了保住partition数据的可靠性，Kafka会为每个partition创建副本均衡地保持在集群的其他broker上，**一个broker上只保持partition的一个的副本**。如图Broker-0的Topic1下的两个Partition1和Partition2分别被放在了。
 3. 同一个Partition中的多个broker, 由一个leader和多个replica组成。而这个leader是有Controller负责选举。leader负责具有读写功能，而replica只有读功能。

# 三. Controller
Controller在Zookeeper注册Watch，一旦有Broker异常，其在Zookeeper对应的znode会自动被删除，Zookeeper会fire Controller注册的watch，Controller读取最新的幸存的Broker

下图展示了选举的整个交互过程： 
（1）每个代理节点(broker)上都有一个控制器(不是主控制器或中央控制器)，会在集群中注册一个/controller节点的事件监听器，关注该节点的变化。
 (2) 刚启动的时候各个控制器会尝试去创建一个/controller临时节点，但是只有一个控制器能够创建成果，并成为中央控制器。用来管理整个集群节点和负责与Zk的交互。
（3）当session重连，或者/controller节点被删除，则发起重新选举。其他各个控制器就有机会重新参与选举。在重新选举之前，先判断自己是否旧的Controller，如果是，则先调用onResignation退位。 

![](/images/15189636136065.jpg)


## 3.1 topic与partition的增加／删除
作为1个分布式集群，当增加／删除一个topic或者partition的时候，不可能挨个通知集群的每1台机器。

这里的实现思路也是：管理端(Admin/TopicCommand)把增加/删除命令发送给Zk，Controller监听Zk获取更新消息, Controller再通知该topic或partition相关的broker, 发送数据同步请求。

# 四. Data Replication
## 4.1 如何选择leader 

每个partition具有一个leader，多个follower. 这个Leader如何选举呢？因为Kafka的Controller掌握了集群中所有节点的信息，**partition的leader选举是由Controller来负责选举**。controller会将Leader的改变直接通过RPC的方式（比Zookeeper Queue的方式更高效）通知需为此作出响应的Broker。同时controller也负责增删Topic以及Replica的重新分配。那么Controller是如何完成这个leader的选举，以及当Leader宕机了，怎样在Follower中选举出新的Leader。

因为Follower可能落后许多或者crash了，所以必须确保选择“最新”的Follower作为新的Leader。一个基本的原则就是，如果Leader不在了，新的Leader必须拥有原来的Leader commit过的所有消息。

Kafaka在Zookeeper中动态维护了一个同步状态的副本的集合（**in-sync replicas**），简称ISR。**在这个集合中的节点都是和leader保持高度一致的**，任何一条消息必须被这个集合中的每个节点读取并追加到日志中了，才回通知外部这个消息已经被提交了。因此这个集合中的任何一个节点随时都可以被选为leader。ISR中有f+1个节点，就可以允许在f个节点down掉的情况下不会丢失消息并正常提供服。ISR的成员是动态的，如果一个节点被淘汰了，当它重新达到“同步中”的状态时，他可以重新加入ISR。因此如果leader宕了，直接从ISR中选择一个follower就行。 

为什么不用少数服从多数的方法：
少数服从多数是一种比较常见的一致性算法和Leader选举法。它的含义是只有超过半数的副本同步了，系统才会认为数据已同步；选择Leader时也是从超过半数的同步的副本中选择。**这种算法需要较高的冗余度**。譬如只允许一台机器失败，需要有三个副本；而如果只容忍两台机器失败，则需要五个副本。而kafka的ISR集合方法，分别只需要两个和三个副本。


如果所有的ISR副本都失败了怎么办？
kafka提供了以下两种选择:
 
 - 等待ISR中的任何一个节点恢复并担任leader。 
 - 选择所有节点中（不只是ISR）第一个恢复的节点作为leader。 
 
如果要等待ISR副本复活，虽然可以保证一致性，但可能需要很长时间。而如果选择立即可用的副本，则很可能该副本并不一致。
 
## 4.2 如何将所有Replica均匀分布到整个集群
为了更好的做负载均衡，Kafka尽量将所有的Partition均匀分配到整个集群上。。一个典型的部署方式是一个Topic的Partition数量大于Broker的数量。同时为了提高Kafka的容错能力，也需要将同一个Partition的Replica尽量分散到不同的机器。Kafka采用轮询分配的方式，将Broker均匀分散在不同broker上.算法如下：

```
（1）对所有的broker和partion进行排序
 (2) 随机从broker列表(Broker 0, Broker 1, Broker 2)中随机选取一个下标startIndex。同时随机生成一个nextReplicaShift，取值范围[0, nBrokers - 1], nBrokers表示broker数量。
 (3) 从Partion 0开始遍历所有的Partition. 执行以下操作：
     1. 每个Partition i的第一个replica（0），的存储位置firstReplicaIndex=(i + startIndex) % brokerList.size。即假如startIndex=4，一个由5个broker. Partition 0的第一个副本则放在Broker 4中。Partition 1第一个replica放在Broker 5中，Partition 2的第一个replica放在Broker 0。以此类推。
     2. 对于每个partition的其他replica j(j>0)，根据j和shift之和作为偏移量，存放在第一个replica后的第(j+shift)个broker中。考虑轮询问题，具体存放的位置计算公式:
        var shift = 1 + (secondReplicaShift + j) % (nBrokers - 1)
        idx = (firstReplicaIndex + shift) % nBrokers
     3. 如果Partition 数量很多，并且broker分配轮流一圈了，那么将nextReplicaShift值加1。

```

Partition的第一个Replica是存放在Leader，而其他Replica存放在Follower上。
举个例子，假设有5个Brokers（broker-0、broker-1、broker-2、broker-3、broker-4），Topic有10个Partition（p0、p1、p2、p3、p4、p5、p6、p7、p8、p9），每一个Partition有3个Replica，依据上述工作过程，分配结果如下：
 
 
```
broker-0  broker-1  broker-2  broker-3  broker-4    broker-5
p0           p1            p2           p3            p4       (1st replica)
p5           p6            p7           p8            p9       (1st replica)
p4           p0            p1           p2            p3       (2nd replica)
p8           p9            p5           p6            p7       (2nd replica)
p3           p4            p0           p1            p2       (3nd replica)
p7           p8            p9           p5            p6       (3nd replica)
```
 
详细步骤如下：
 
选取broker-0作为StartingBroker，IncreasingShift初始值为1，
 
对于p0，replica1分配至broker-0，IncreasingShift为1，所以replica2分配至broker-1，replica3分配至broker-2；
对于p1，replica1分配至broker-1，IncreasingShift为1，所以replica2分配至broker-2，replica3分配至broker-3；
对于p2，replica1分配至broker-2，IncreasingShift为1，所以replica2分配至broker-3，replica3分配至broker-4；
对于p3，replica1分配至broker-3，IncreasingShift为1，所以replica2分配至broker-4，replica3分配至broker-1；
对于p4，replica1分配至broker-4，IncreasingShift为1，所以replica2分配至broker-0，replica3分配至broker-1；
 
注：IncreasingShift用于计算Shift，Shift表示Partition的第n（n>=2）个Replica与第1个Replica之间的间隔量。如果IncreasingShift值为m，那么Partition的第2个Replica与第1个Replica的间隔量为m + 1，第3个Replica与第1个Replica的间隔量为m + 2，...，依次类推。Shift的取值范围：[1，brokerSize - 1]。
 
此时，broker-0、broker-1、broker-2、broker-3、broker-4分别作为StartingBroker被轮询分配一次，继续轮询；但IncreasingShift递增为2。
 
对于p5，replica1分配至broker-0，IncreasingShift为2，所以replica2分配至broker-2，replica3分配至broker-3；
对于p6，replica1分配至broker-1，IncreasingShift为2，所以replica2分配至broker-3，replica3分配至broker-4；
对于p7，replica1分配至broker-2，IncreasingShift为2，所以replica2分配至broker-4，replica3分配至broker-0；
对于p8，replica1分配至broker-3，IncreasingShift为2，所以replica2分配至broker-0，replica3分配至broker-1；
对于p9，replica1分配至broker-4，IncreasingShift为2，所以replica2分配至broker-1，replica3分配至broker-2；
 
此时，broker-0、broker-1、broker-2、broker-3、broker-4分别作为StartingBroker再次被轮询一次，如果还有其它Partition，则继续轮询，IncreasingShift递增为3，依次类推。

**为什么要随机选取StartingBroker，而不是每次都选取broker-0作为StartingBroker?**
因为分配过程是以轮询方式进行的，如果每次都选取broker-0作为StartingBroker，那么Brokers列表中的前面部分将有可能被分配相对比较多的Partition Replicas，从而导致这部分Brokers负载较高，随机选取可以保证相对比较好的均匀效果。

**为什么Brokers列表每次轮询一次，IncreasingShift值都需要递增1？**
如果主题的分区数多于Broker的个数，如果不在用递增方式则多余的分区都是倾向于将分区发放置在前几个Broker上，同样导致负载不均衡。Kafka Topic Partition数目较多的情况下，间隔量随着每一个轮询递增能够更好的均匀分配Replica。


## 4.3 分布式系统下数据发布到读取过程

![](/images/15189498382789.jpg)

1. Producer要发布数据时首先去Zookeeper中获取partition对应的Leader
2. Producer像Leader的broker发送消息，Leader会将该消息写入其本地Log。
3. 该partition对应的Follower都从Leader中pull 数据。Follower存储的数据顺序与Leader保持一致
4. 为了提高性能每个Follower在接收到数据后就立马向Leader发送ACK，然后将数据写入Log。
5. 一旦Leader收到了ISR中的所有Replica的ACK，该消息就被认为已经commit了，Leader向Producer发送ACK并且更新ISR。

Kafka通过牺牲数据的可靠性换取push性能。如果等待Follower写入log以后再回复ACK，虽然能保证一致性，但是可能导致producer等待很久。但是这种直接返回ACK，再写log, Kafka只能保证它被存于多个Replica的内存中，而不能保证它们被持久化到磁盘中，也就不能完全保证异常发生后该条消息一定能被Consumer消费。

而对于Producer而言，它可以选择是否等待消息commit，这可以通过request.required.acks来设置。这种机制确保了只要ISR有一个或以上的Follower，一条被commit的消息就不会丢失。 　　


# 思考

- 为什么是采用partition维度创建副本？而不是Topic?
- Follower只负责读。只有leader和producer、consumer交互？
- 是否有补发机制？如果Foller在某一次replica写数据宕机或失败，是否会重新从Leader获取这条数据重新写。
- “ 为了提高性能每个Follower在接收到数据后就立马向Leader发送ACK，然后将数据写入Log。”是默认这样么？还是有提供给用户选择


# 参考
 - [Kafka的分布式架构设计与High Availability机制](http://josh-persistence.iteye.com/blog/2234636)
 - [kafka leader选举机制原理](http://blog.csdn.net/yanshu2012/article/details/54894629)
 - [Kafka设计解析（三）- Kafka High Availability （下）](http://www.jasongj.com/2015/06/08/KafkaColumn3/)
 - [Kafka controller重设计](https://www.cnblogs.com/huxi2b/p/6980045.html)
 - [Kafka源码深度解析－序列11 －Server核心组件之1－KafkaController选举过程/Failover与Resignation](http://blog.csdn.net/chunlongyu/article/details/52933947)
 - [zookeeper与kafka的选举算法](http://blog.csdn.net/yu280265067/article/details/62868969) | 分别描述了两种算法思路，并做了一些对比
 - [Kafka Topic Partition Replica Assignment实现原理及资源隔离方案](https://www.cnblogs.com/yurunmiao/p/5550906.html)
  


