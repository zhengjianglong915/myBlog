title: JDK源码学习--ThreadLocal
date: 2015-10-11 20:38:51
description: ThreadLocal是线程局部变量，其中保存了特定于该线程的值.每个线程都拥有一份独立的副本值，即每个线程修改变量值不影响其他线程该变量的副本值.这些特定于线程的值保存在Thread对象中，当线程终止后，这些值会作为垃圾回收．有一点值得注意的时该类是在java.lang包中，而不是在java.concurrent包中．
categories: Java
tags:
    - Java
---

ThreadLocal是线程局部变量，其中保存了特定于该线程的值.每个线程都拥有一份独立的副本值，即每个线程修改变量值不影响其他线程该变量的副本值.这些特定于线程的值保存在Thread对象中，当线程终止后，这些值会作为垃圾回收．有一点值得注意的时该类是在java.lang包中，而不是在java.concurrent包中．

如果没有看源码可能会认为ThreadLocal内部的实现方式应该是采用Map容器，保存一个<Thread,T>的映射关系．然而JDK内部并不是这么实现的，而是在Thread类中加入了一个散列表(ThreadLocalMap是ThreadLocal的静态内部类)来维护当前线程的所有局部变量值(即当前线程中的所有ThreadLocal变量)，通过散列表数据结构可以快速地执行get和set操作.


### 散列
每次创建的ThreadLocal都有唯一的hashCode值，根据这个值hashCode可以计算变量在散列表中对应的地址．ThreadLocalMap的hash函数方法是将hashCode值和散列表容量大小进行与操作得到变量对应的位置．

	int i = firstKey.threadLocalHashCode & (INITIAL_CAPACITY - 1);

### 冲突解决
在散列表中会存在地址冲突问题，即对于不同的hashCode可能会计算得到地址．对于这种情况，ThreadLocalMap采用了最简单的冲突解决方案---从冲突发生的地址d开始，依次探测d的下一个地址，直到找到一个空闲单元为止.

### 装填因子
ThreadLocalMap　设置的装填因子为2/3，当变量个数大于2/3时扩大容器容量再散列．

### get和set
ThreadLocal的定义和使用比较简单，只要声明一个ThreadLocal变量，那该变量就为每个线程都分配了一个副本.通过set和get方法设置和获取该线程局部变量值： 

	ThreadLocal<Integer> integerLocal = new ThreadLocal<Integer>();
	integerLocal.set(1);
	Integer i = integerLocal.get();

对于以上的set和get方法的实现思路也笔记简单．在set方法中，首先查看当前线程是否初始化了散列表，如果没有则创建一个散列表(初始化容器大小为16)．如果存在则根据hashCode计算变量在散列表的地址并设置值．

	public void set(T value) {
		Thread t = Thread.currentThread();
		ThreadLocalMap map = getMap(t);
		if (map != null)
		    map.set(this, value);
		else
		    createMap(t, value);
	}

get方法和set方法相似，如果散列表不存在时则创建一个散列表并设置初始值．

	public T get() {
		Thread t = Thread.currentThread();
		ThreadLocalMap map = getMap(t);
		if (map != null) {
		    ThreadLocalMap.Entry e = map.getEntry(this);
		    if (e != null) {
		        @SuppressWarnings("unchecked")
		        T result = (T)e.value;
		        return result;
		    }
		}
		return setInitialValue();
	 }


