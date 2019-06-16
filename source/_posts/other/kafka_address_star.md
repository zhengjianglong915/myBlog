title: 技术文章地址集锦
date: 2018-02-06 20:31:00
description: 整理了自己在学习各个技术过程中遇到的好文章和博客，将这些优秀技术文章和博客地址分类收藏，编译以后回顾和学习。
categories: 收藏
tags:
    - 收藏
---
# 语言
## GO
### 使用
- [探究golang接口](https://studygolang.com/articles/2566) |  对比对C/C++相关知识进一步理解golang的接口、指针、参数传递   
- [Go语言高级进阶篇系列](http://blog.csdn.net/column/details/gosenior.html?&page=2)
- [golang内存线程池](https://liudanking.com/arch/golang-multi-level-memory-pool-design-implementation/?hmsr=toutiao.io&utm_medium=toutiao.io&utm_source=toutiao.io)
- [《Go语言圣经（中文版）》](https://books.studygolang.com/gopl-zh/)
- [https://studygolang.com/articles/7366](https://studygolang.com/articles/7366)

# 消息队列
## Kafka
### 入门和开发
  - [kafka官方英文文档](https://kafka.apache.org/documentation/)  
  - [kafka中文文档](http://www.orchome.com/kafka/index?spm=a2c4e.11153940.blogcont69501.5.6b095fb6Ku7S1K)    
  - [jafka，java版Kafka](https://github.com/adyliu/jafka)
  
### Kafka设计
  - [kafka design-官网](http://kafka.apache.org/design.html) | Kafka官网提供的关于Kafka设计的文章，最为权威，里面有好多理念都特别好，推荐多读几遍
  - [分布式发布订阅消息系统 Kafka 架构设计](http://www.oschina.net/translate/kafka-design) 
  
  对应官网kafka design的中文翻译，不过该版本未及时更新还停留在2013年的kafka版本，所以建议还是自己看官网文档
  - [Kafka设计理念浅析](http://rockybean.github.io/2012/07/30/jafka-design/?spm=a2c4e.11153940.blogcont69501.28.6b095fb674F3ju) 
  
  写了Kakfa的几个设计特色：消息数据通过磁盘线性存取、强调吞吐率、消费状态由消费者自己维护、分布式。操作系统、JVM等层面分析各个特色设计带来的收益。
  
  - [Kafka实现细节（上）](https://my.oschina.net/ielts0909/blog/94153)
   
    总结了Kafka底层的实现依赖如：依赖操作系统随机读写、操作系统的缓存特性、 Zero-copy、 事务机制、Liner writer/reader。
  
### 源码阅读
- [Kafka设计解析系列](http://www.jasongj.com/tags/Kafka/?spm=a2c4e.11153940.blogcont69501.23.6b095fb6wkUJ2N)
- [travi. Kafka源码阅读系列](http://blog.csdn.net/chunlongyu/article/list/3)


### 其他
 - [Gaischen. kafka系列文章索引](https://my.oschina.net/ielts0909/blog/117489)
 - [apache kafka技术分享系列(目录索引)](http://blog.csdn.net/lizhitao/article/details/39499283)

## NSQ
### 入门与开发
- [NSQ：分布式的实时消息平台](http://www.infoq.com/cn/news/2015/02/nsq-distributed-message-platform/) |  InfoQ  | 介绍了Nsq的一些特点，大部分都是翻译官方文档
- [初识NSQ分布式实时消息架构](http://blog.csdn.net/charn000/article/details/48109665)


### 设计
- [深入NSQ 之旅](https://www.oschina.net/translate/day-22-a-journey-into-nsq?lang=chs&page=1#) | 翻译了《A Journey Into NSQ》，主要从设计层面分析NSQ
- [A Journey Into NSQ](https://blog.gopheracademy.com/advent-2013/day-22-a-journey-into-nsq/)
- [NSQ：分布式的实时消息平台](http://www.infoq.com/cn/news/2015/02/nsq-distributed-message-platform/) 

### 源码学习
- [nsq源码分析（1）：代码结构](http://blog.csdn.net/shanhuhai5739/article/details/72898646)
- [NSQ源码分析之nsqlookupd](http://luodw.cc/2016/12/13/nsqlookupd/) | 罗道文的私房菜
- [shanhuhai5739](http://my.csdn.net/shanhuhai5739)






