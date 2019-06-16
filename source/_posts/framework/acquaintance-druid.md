title: druid剖析(1)--初始 druid 
layout: post
date: 2019-06-16 09:12:43
comments: true
categories: "测试框架"
tags: 
    - Druid
    - 数据库

keywords: Druid 
description: 数据库连接是一种关键的有限的昂贵的资源，对数据库连接的管理能显著影响到整个应用程序的伸缩性和健壮性，影响到程序的性能指标。数据库连接池正是针对这个问题提出来的。数据库连接池负责分配、管理和释放数据库连接，它允许应用程序重复使用一个现有的数据库连接，而不是再重新建立一个；释放空闲时间超过最大空闲时间的数据库连接来避免因为没有释放数据库连接而引起的数据库连接遗漏。这项技术能明显提高对数据库操作的性能。

---


# 一、介绍
## 什么是数据连接池
数据库连接是一种关键的有限的昂贵的资源，对数据库连接的管理能显著影响到整个应用程序的伸缩性和健壮性，影响到程序的性能指标。数据库连接池正是针对这个问题提出来的。数据库连接池负责分配、管理和释放数据库连接，它允许应用程序重复使用一个现有的数据库连接，而不是再重新建立一个；释放空闲时间超过最大空闲时间的数据库连接来避免因为没有释放数据库连接而引起的数据库连接遗漏。这项技术能明显提高对数据库操作的性能。



使用线程池带来的收益有：

- 避免频繁创建和关闭连接，减少服务性能开销。
- 提高响应速度，当需要连接时直接从连接池获取，省略了连接创建过程。


举一反三：

在服务开发中有很多类似的模型，当资源比较昂贵，可以使用资源复用方式提高性感。常见的有：

- 线程池。和连接池一样，都是为了共享资源，减少开销。线程池负责管理和分配线程的使用。
- 资源池。可以比较复杂的资源对象，提前构建后存入资源池，重复利用。
 

## Druid
Driud 是阿里巴巴的一个为监控而生的数据库连接池,是在阿里巴巴监控系统Dragoon系统中演化而来的副产品。该项目扩展了JDBC的一些限制，可以让程序员实现一些特殊的需求，比如向密钥服务请求凭证、统计SQL信息、SQL性能收集等，程序员可以通过定制来实现自己需要的功能。 该产品主要由三个部分组成:

- DruidDataSource 高效可管理的数据库连接池.
- DruidDriver 代理Driver，能够提供基于Filter－Chain模式的插件体系. 通过插件来拓展功能，拓展更加灵活。
- SQL Parser。 通过Druid提供的SQL Parser可以在JDBC层拦截SQL做相应处理，比如说分库分表、审计等

所支持的数据库：

- Druid支持所有JDBC兼容的数据库，包括Oracle、MySql、Derby、Postgresql、SQL Server、H2等等。 

- Druid针对Oracle和MySql做了特别优化，比如Oracle的PS Cache内存占用优化，MySql的ping检测优化



### 1.1 功能
1) Druid提供了一个高效、功能强大的数据库连接池
通过官方压测数据，druid 相对其他数据库连接池来说性能较好。
druid 除了提供基本的数据库连接功能外，还提供了 sql 监控、密码加密、拦截器等功能。


2) 监控数据库访问性能
Druid内置提供了一个功能强大的StatFilter插件, 能够完成以下工作：

- 监控SQL的执行时间、ResultSet持有时间、返回行数、更新行数、错误次数、错误堆栈信息。
SQL执行的耗时区间分布。
- 监控连接池的物理连接创建和销毁次数、逻辑连接的申请和关闭次数、非空等待次数、PSCache命中率等。
- 监控统计功能是通过filter-chain扩展实现



3) 可扩展好
Druid在DruidDataSourc和ProxyDriver上提供了Filter-Chain模式的扩展API，类似Serlvet的Filter，配置Filter拦截JDBC的方法调用。 根据该设计，开发人员可以自己编写Filter拦截JDBC中的任何方法，可以在上面做任何事情，比如说性能监控、SQL审计、用户名密码加密、日志等等。

Druid内置提供了用于监控的StatFilter、日志输出的Log系列Filter、防御SQL注入攻击的WallFilter
数据库密码加密的CirceFilter，以及和Web、Spring关联监控的DragoonStatFilter


4) 防御SQL注入攻击
它是基于SQL语义分析来实现防御SQL注入攻击的, `如何实现？`

5) SQL执行日志
Druid提供了不同的LogFilter，能够支持Common-Logging、Log4j和JdkLog，你可以按需要选择相应的LogFilter，监控你应用的数据库访问情况，监控 sql 执行性能。



### 1.2 性能
Druid集合了开源和商业数据库连接池的优秀特性，并在该基础上做了一些优化。

- PSCache内存占用优化对于支持游标的数据库（Oracle、SQLServer、DB2等，不包括MySql），PSCache可以大幅度提升SQL执行性能。 (`是如何实现的？`)
- 数据库连接池遵从LRU，有助于数据库服务器优化
Druid性能比DBCP、C3P0、Proxool、JBoss都好
SQL性能高效


### 1.3  拓展性
通过Filter-Chain的设计，可以让程序员实现一些特殊的需求，比如向密钥服务请求凭证、统计SQL信息、SQL性能收集、SQL注入检查、SQL翻译等，程序员可以通过定制来实现自己需要的功能。



### 1.4 优势
强大的监控特性，通过Druid提供的监控功能，可以清楚知道连接池和SQL的工作情况。 
Druid集合了开源和商业数据库连接池的优秀特性
Druid的优势是在JDBC最低层进行拦截做判断，不会遗漏。

### 1.5  各种数据库连接池对比
官网对比：https://github.com/alibaba/druid/wiki/%E5%90%84%E7%A7%8D%E6%95%B0%E6%8D%AE%E5%BA%93%E8%BF%9E%E6%8E%A5%E6%B1%A0%E5%AF%B9%E6%AF%94

| 对比维度/连接池 | Druid | BoneCP | DBCP | C3P0 | Proxool | JBoss | Tomcat-Jdbc | HikariCP |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 主要功能对比(是否支持) |
|LRU| 是	| 否|	是|	否|	是|	是|	？|	 
|PSCache|	是|	是|	是|	是|	否|	否|	是|	否|
|PSCache-Oracle-Optimized|	是|	否|	否|	否|	否|	否|	否|	否|
|ExceptionSorter|	是|	否|	否|	否|	否|	是|	否|
|更新维护|	是|	否|	否|	否|	否|	?|	是|
|设计思路	| 	两个线程： 其中一个负责异步创建。一个负责最小连接数的维持。 其中心跳是通过获取连接，来判定是否小于心跳间隔。|	已经被HikariCP替代|	一个线程：负责心跳，最小连接数维持，最大空闲时间和防连接泄露。	| 四个线程；三个helperThread （pollerThread）,一个定时AdminTaskTimer（DeadlockDetector）||||三个线程： 其中一个为定时线程，解决最大空闲时间。两个为新建连接和关闭连接。 均是连接池，空闲5s，线程便会关闭。	 |
| 拓展性|	 好|	较好|	弱|	弱|	 ||弱	 |弱|
|稳定性|	 ||||	 	 	 	 	差，高并发下出错||||	 	 	 
	 	 
 	 	 	 	 	 	 	 	 	
- ExceptionSorter：
当网络断开或者数据库服务器Crash时，连接池里面会存在“不可用连接”，连接池需要一种机制剔除这些“不可用连接”。在Druid和JBoss连接池中，剔除“不可用连接”的机制成为ExceptionSorter，实现的原理是根据异常类型/Code/Reason/Message来识别“不可用连接”。没有ExceptionSorter的连接池，在数据库重启或者网络中断之后，不能恢复工作，所以ExceptionSorter是连接池是否稳定的重要标志。

- 性能对比参见：https://github.com/alibaba/druid/wiki/linux-benchmark

- 性能表现：hikariCP>druid>tomcat-jdbc>jboss>dbcp>proxool>c3p0>BoneCP。hikariCP 的性能极奇优异
- hikariCP号称java平台最快的数据库连接池。
 hikariCP在并发较高的情况下，性能基本上没有下降。hikariCP的高性能得益于最大限度的避免锁竞争。
 c3p0连接池的性能很差，不建议使用该数据库连接池。
- proxool在并发较高的情况下会出错
- HikariCP做了一些优化，总结(官网)如下：
    - 字节码精简：优化代码，直到编译后的字节码最少，这样，CPU缓存可以加载更多的程序代码；
    - 优化代理和拦截器：减少代码，例如HikariCP的Statement proxy只有100行代码，只有BoneCP的十分之一；
    - 自定义数组类型（FastStatementList）代替ArrayList：避免每次get()调用都要进行range check，避免调用remove()时的从头到尾的扫描；
    - 自定义集合类型（ConcurrentBag）：提高并发读写的效率；
    - 其他针对BoneCP缺陷的优化，比如对于耗时超过一个CPU时间片的方法调用的研究。
 
五、参考

- [github][druid github](https://github.com/alibaba/druid)
- [github][druid wiki](https://github.com/alibaba/druid/wiki)
- [ITeye][阿里巴巴开源项目 Druid 负责人温少访谈](http://www.iteye.com/magazines/90#111)
- [开源中国][JDBC连接池、监控组件 Druid](https://www.oschina.net/p/druid)
- [druid 源码分析与学习（含详细监控设计思路的彩蛋）](http://blog.csdn.net/herriman/article/details/51759479)
- [HikariCP](http://www.cnblogs.com/xingzc/p/6073730.html)
- [数据库连接池性能比对(hikari druid c3p0 dbcp jdbc)](http://blog.csdn.net/qq_31125793/article/details/51241943)
- [数据库连性池性能测试(hikariCP,druid,tomcat-jdbc,dbcp,c3p0)](http://blog.csdn.net/not_in_mountain/article/details/77829159)


