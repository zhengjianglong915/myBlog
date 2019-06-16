title: Mybatis源码解析(4)--数据源与连接池
layout: post
date: 2018-02-16 09:28:09
comments: true
categories: Mybatis源码解析
tags: 
    - 源码解析
    - Mybatis
    
keywords: “Mybatis”
description: Mybatis作为一个数据操作中间件，支持三种内建三种类型的DataSource， 即 UNPOOLED, POOLED 和 JNDI. 本文主要是分析Mybatis源码中如何支持和实现三种数据源、数据库连接、以及事务。

---

# 一. 数据源

MyBatis 支持三种内建的 DataSource 类型: UNPOOLED, POOLED和JNDI，并分别提供了实现方法.

 - **UNPOOLED**类型的数据源dataSource为每一个用户请求创建一个数据库连接。在多用户并发应用中，不建议使用。Mybatis提供了实现DataSource接口的UnpooledDataSource。 - **POOLED**类型的数据源dataSource创建了一个数据库连接池，对用户的每一个请求，会使用缓冲池中的一个可用的Connection对象,这样可以提高应用的性能。MyBatis 提 供 了 PooledDataSource实现javax.sql.DataSource来创建连接池。其实现依赖于UnpooledDataSource。- **JNDI**类型的数据源dataSource使用了应用服务器的数据库连接池，并且使用JNDI查找来获取数据库连接。通过JNDI上下文中取值。


MyBatis通过工厂模式来创建数据源DataSource对象，因此为三种type的数据源分别都提供了一个生成工厂：

 - POOLED对应工厂PooledDataSourceFactory。负责生成PooledDataSource。
 - UNPOOLED对应工厂UnpooledDataSourceFactory，负责生成UnpooledDataSource
 - JNDI对应工厂JndiDataSourceFactory

其类图如图所示：
![](/images/15187485821776.jpg)



## 1.1 数据源DataSource的创建过程
MyBatis数据源DataSource对象的创建发生在MyBatis初始化的过程中。XMLConfigBuilder解析mybatis-config.xml各个节点，并将解析后的结果存放在configuration中。mybatis-config.xml数据源配置如下：

```
<environments default="development">
    <environment id="development">
        <transactionManager type="JDBC"/>
        <dataSource type="POOLED">
            <property name="driver" value="com.mysql.jdbc.Driver"/>
            <property name="url" value="jdbc:mysql://localhost:3306/test_db"/>
            <property name="username" value="root"/>
            <property name="password" value="admin"/>
        </dataSource>
    </environment>
</environments>
```

XMLConfigBuilder中以下代码就是完成environments节点的解析，并生成DataSource和事务transaction.

```
environmentsElement(root.evalNode("environments"));
```

Configuration在初始化的时候为Mybatis的事物和DataSource都设置了别名，在配置中只要设置别名则可。如上面的配置中，事务管理器是JDBC，dataSource采用POOLED。 JDBC配置的事务工厂是JdbcTransactionFactory， POOLED配置的工厂是PooledDataSourceFactory。

```
typeAliasRegistry.registerAlias("JDBC", JdbcTransactionFactory.class);
typeAliasRegistry.registerAlias("MANAGED", ManagedTransactionFactory.class);

typeAliasRegistry.registerAlias("JNDI", JndiDataSourceFactory.class);
typeAliasRegistry.registerAlias("POOLED", PooledDataSourceFactory.class);
typeAliasRegistry.registerAlias("UNPOOLED", UnpooledDataSourceFactory.class);
```

因此只要根据事务的type和datasource的type就可以获得对应工厂，然后利用工厂生成对应的对象。这里采用的是工厂模式：

```
private void environmentsElement(XNode context) throws Exception {
    if (context != null) {
      if (environment == null) {
        environment = context.getStringAttribute("default");
      }
      for (XNode child : context.getChildren()) {
        String id = child.getStringAttribute("id");
        if (isSpecifiedEnvironment(id)) {
          // 根据事务类型生成事务工厂
          TransactionFactory txFactory = transactionManagerElement(child.evalNode("transactionManager"));
          // 根据dataSource配置，生成对应的工厂
          DataSourceFactory dsFactory = dataSourceElement(child.evalNode("dataSource"));
          // 生成DataSource
          DataSource dataSource = dsFactory.getDataSource();
          Environment.Builder environmentBuilder = new Environment.Builder(id)
              .transactionFactory(txFactory)
              .dataSource(dataSource);
          configuration.setEnvironment(environmentBuilder.build());
        }
      }
    }
  }
```

以上便完成了事务工厂的获取和DataSource的生成。最后保存到configuration中，供后续操作使用。注意这边没有直接生成事务，事务与具体操作相关，在需要使用事务操作的时候，MyBatis利用这个事务工厂来生产事务。事务工厂和DataSource在configuration中的存储结构如图所示：

![](/images/15187499434511.jpg)

## 1.2 生成DataSource
下面说下三种数据源工厂如何生成数据源的。

### 1.2.1 UnpooledDataSourceFactory和PooledDataSourceFactory
这种类型的数据源dataSource为每一个用户请求创建一个数据库连接。在并发情况下会创建大量的请求连接，连接的利用率很低，而且大量消耗性能。如果数据库请求很少，这种方式还是具有其优势如：节省内存使用、简单。

在工厂内部是直接new一个UnpooledDataSource对象:

```
public UnpooledDataSourceFactory() {
    this.dataSource = new UnpooledDataSource();
}
```

PooledDataSourceFactory首先继承了UnpooledDataSourceFactory。其实现也很简单，直接new一个对应的对象就可以:

```
public PooledDataSourceFactory() {
    this.dataSource = new PooledDataSource();
}
```

## 1.2.2 JndiDataSourceFactory
MyBatis定义了一个JndiDataSourceFactory工厂来创建通过JNDI形式生成的DataSource。下面让我们看一下JndiDataSourceFactory的关键代码：

```
 if (properties.containsKey(INITIAL_CONTEXT)
          && properties.containsKey(DATA_SOURCE)) {
    // 从JNDI上下文中找到DataSource并返回
    Context ctx = (Context) initCtx.lookup(properties.getProperty(INITIAL_CONTEXT));
    dataSource = (DataSource) ctx.lookup(properties.getProperty(DATA_SOURCE));
  } else if (properties.containsKey(DATA_SOURCE)) {
    // 从JNDI上下文中找到DataSource并返回
    dataSource = (DataSource) initCtx.lookup(properties.getProperty(DATA_SOURCE));
  }
```

# 二. 数据库连接池

UNPOOLED类型的数据源，为每个用户请求都会创建一个数据库连接。如果是几个用户请求操作，创建数据库连接带来的性能损耗可以忽略。但是应用存在大量的或并发的数据库请求的时候，这种创建数据库连接的操作带来的性能损耗累计是非常可观的。

创建一个java.sql.Connection对象的代价是如此巨大，是因为创建一个Connection对象的过程，在底层就相当于和数据库建立的通信连接，在建立通信连接的过程，消耗了这么多的时间，而往往我们建立连接后（即创建Connection对象后），就执行一个简单的SQL语句，然后就要抛弃掉，这是一个非常大的资源浪费。

为了减少性能开心性能开销，Mybatis提供了POOLED类型的数据库源DataSource，内置了数据库连接池.对于需要频繁地跟数据库交互的应用程序，可以在创建了Connection对象，并操作完数据库后，可以不释放掉资源，而是将它放到内存中，当下次需要操作数据库时，可以直接从内存中取出Connection对象，不需要再创建了，这样就极大地节省了创建Connection对象的资源消耗。由于内存也是有限和宝贵的，这又对我们对内存中的Connection对象怎么有效地维护提出了很高的要求。我们将在内存中存放Connection对象的容器称之为连接池（Connection Pool）。下面让我们来看一下MyBatis的连接池是怎样实现的。


## 2.1 数据结构
PooledDataSource内置的数据库连接池保存在PoolState中：

```
private final PoolState state = new PoolState(this);
```

PoolState作为PooledDataSource的数据库连接池，为了便于管理数据库连接Connection, PoolState几个重要属性如下:

```
// 存储空闲的连接Conncection
protected final List<PooledConnection> idleConnections = new ArrayList<PooledConnection>();
// 存储活动中(使用中)的Conncection
protected final List<PooledConnection> activeConnections = new ArrayList<PooledConnection>();
// 数据源，用于创建连接
protected PooledDataSource dataSource;

```
可以用下图来表示：

![](/images/15187642454569.jpg)


## 2.2 获取Connection对象的过程
[Mybatis源码解析(3)--SqlSession工作过程分析](http://zhengjianglong.cn/2018/02/15/mybatis/Mybatis%E6%BA%90%E7%A0%81%E8%A7%A3%E6%9E%90(3)--SqlSession%E5%B7%A5%E4%BD%9C%E8%BF%87%E7%A8%8B%E5%88%86%E6%9E%90/) 中我们分析了Sql的执行过程，在MapperMethod中，会调用Executor执行sql操作。SimpleExecutor首先会获取连接然后执行数据库操作：

```
// SimpleExecutor
private Statement prepareStatement(StatementHandler handler, Log statementLog) throws SQLException {
    Statement stmt;
    Connection connection = getConnection(statementLog);
    stmt = handler.prepare(connection, transaction.getTimeout());
    // 对创建的Statement对象设置参数，即设置SQL 语句中 ? 设置为指定的参数
    handler.parameterize(stmt);
    return stmt;
}
```

getConnection方法完成了connection的获取，而该方法内部Connection的获取交个了Transaction. 上文的配置信息中我们使用了JDBC类型的Transaction, 其实现类是JdbcTransaction。最终JdbcTransaction将数据库的获取交给了数据源DataSource， 即PooledDataSource。

```
/**
 * JdbcTransaction 
**/
protected void openConnection() throws SQLException {
    if (log.isDebugEnabled()) {
      log.debug("Opening JDBC Connection");
    }
    connection = dataSource.getConnection();
    if (level != null) {
      connection.setTransactionIsolation(level.getLevel());
    }
    setDesiredAutoCommit(autoCommmit);
}
```

PooledDataSource为对连接Connection进行管理提供了连接池代理对象PooledConnection，特别是在connection执行close的时候存放到数据库连接池中，而不是真正关闭。 代理对象对connection的每个方法进行动态代理：
```
this.proxyConnection = (Connection) Proxy.newProxyInstance(Connection.class.getClassLoader(), IFACES, this);
```

在执行Connection的任何方法的时候都会调用PooledConnection的invoke方法。这块逻辑留在后面讲述，这里我们先说下如何从PooledDataSource获取Connection:

![](/images/15187444882302.jpg)


dataSource.getConnection()方法本质上是调用了PoolDataSource.popConnection（）方法，该方法的具体流程如下：
 
  1. 先看是否有空闲(idle)状态下的PooledConnection对象，如果有，就直接返回一个可用的PooledConnection对象；否则进行第2步。

  2. 查看活动状态的PooledConnection池activeConnections是否已满；如果没有满，则创建一个新的PooledConnection对象，然后放到activeConnections池中，然后返回此PooledConnection对象；否则进行第三步；

  3. 因为数据库连接池设置了一个连接最大阈值poolMaximumActiveConnections，创建的连接池数量不能超过这个数目。因此此刻只能等待空闲的连接或者查看使用中的连接是否有已经过期的连接。最先进入activeConnections池中的PooledConnection对象是否已经过期：如果已经过期，从activeConnections池中移除此对象，然后创建一个新的PooledConnection对象，添加到activeConnections中，然后将此对象返回；否则进行第4步。

  4. 线程等待，循环至第1步


数据库连接获取过程有一下几个细节点:

 1. Mybatis空闲Connection的性能不高。因为空闲列表采用ArrayList列表存储， Mybatis数据库连接池每次都是从空闲链表中获取第一个空闲的PooledConnection对象并从List中移除,导致后面的对象需要往前移动拷贝。如果空闲对象数量阈值poolMaxinumIdleConnections很大, 空闲连接对象比较多的情况下，影响性能。 
 2. 如果activeConnection满的情况下，删除过期(超过指定时间)对象每次都是判断activeConnection中的第一个。 
 3. 没有有效管理Connection. Connection在空闲conection中可能因为长时间没用导致连接失效问题，但是这里没有做检查。
 4. 每个连接获取都是线程安全的，通过对PoolState state加锁。

## 2.3 java.sql.Connection对象的回收
当我们的程序中使用完Connection对象时，如果不使用数据库连接池，我们一般会调用 connection.close()方法，关闭connection连接，释放资源。为了和一般的使用Conneciton对象的方式保持一致，我们希望当Connection使用完后，调用.close()方法，而实际上Connection资源并没有被释放，而实际上被添加到了连接池中。该功能的实现，归功于代理对象PooledConnection。PooledConnection对真实连接的每个方法进行拦截、代理。

当我们调用此proxyConnection对象上的任何方法时，都会调用PooledConnection对象内invoke()方法。

```
public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {  
      String methodName = method.getName();  
      //当调用关闭的时候，回收此Connection到PooledDataSource中  
      if (CLOSE.hashCode() == methodName.hashCode() && CLOSE.equals(methodName)) {  
          dataSource.pushConnection(this);  
          return null;  
      } else {  
          try {  
              if (!Object.class.equals(method.getDeclaringClass())) {  
                  checkConnection();  
              }  
              return method.invoke(realConnection, args);  
          } catch (Throwable t) {  
              throw ExceptionUtil.unwrapThrowable(t);  
          }  
      }  
}
```
 
 从上述代码可以看到，当我们使用了pooledDataSource.getConnection()返回的Connection对象的close()方法时，不会调用真正Connection的close()方法，而是将此Connection对象放到连接池中。
 
# 三. 事务 
MyBatis的事务管理分为两种形式：

  - 使用JDBC的事务管理机制：即利用java.sql.Connection对象完成对事务的提交（commit()）、回滚（rollback()）、关闭（close()）等。
  - 使用MANAGED的事务管理机制：这种机制MyBatis自身不会去实现事务管理，而是让程序的容器如（JBOSS，Weblogic）来实现对事务的管理。

MyBatis将事务抽象成了Transaction接口，Configuration在初始的时候就为这两个事务机制设置别名和事务工厂:

```
typeAliasRegistry.registerAlias("JDBC", JdbcTransactionFactory.class);
typeAliasRegistry.registerAlias("MANAGED", ManagedTransactionFactory.class);
```

在配置文件中可以通过以下方式指定事务类型:
```
 <transactionManager type="JDBC"/>
```

## 3.1 事务创建
上文提到mybatis-config.xml解析的时候会根据配置的事物类型获取事务工厂：
```
// 根据事务类型生成事务工厂
TransactionFactory txFactory = transactionManagerElement(child.evalNode("transactionManager"));

```

事务工厂Transaction定义了创建Transaction的两个方法：一个是通过指定的Connection对象创建Transaction，另外是通过数据源DataSource来创建Transaction。与JDBC 和MANAGED两种Transaction相对应，TransactionFactory有两个对应的实现的子类：

![](/images/15187705777701.jpg)


我们看看JdbcTransactionFactory事务工厂如何构建一个事务对象。

```
 @Override
  public Transaction newTransaction(Connection conn) {
    return new JdbcTransaction(conn);
  }
  
  @Override
  public Transaction newTransaction(DataSource ds, TransactionIsolationLevel level, boolean autoCommit) {
    return new JdbcTransaction(ds, level, autoCommit);
  }
```

JdbcTransactionFactory会创建JDBC类型的Transaction，即JdbcTransaction。类似地，ManagedTransactionFactory也会创建ManagedTransaction。下面我们会分别深入JdbcTranaction 和ManagedTransaction，看它们到底是怎样实现事务管理的。

## 3.2 JdbcTransaction
JdbcTransaction直接使用JDBC的提交和回滚事务管理机制。它依赖与从dataSource中取得的连接connection 来管理transaction 的作用域。JdbcTransaction是使用的java.sql.Connection 上的commit和rollback功能，JdbcTransaction只是相当于对java.sql.Connection事务处理进行了一次包装（wrapper），Transaction的事务管理都是通过java.sql.Connection实现的。

```
/** 
* commit()功能 使用connection的commit() 
* @throws SQLException 
*/  
public void commit() throws SQLException {  
  if (connection != null && !connection.getAutoCommit()) {  
      if (log.isDebugEnabled()) {  
          log.debug("Committing JDBC Connection [" + connection + "]");  
      }  
      connection.commit();  
  }  
}  
 
/** 
* rollback()功能 使用connection的rollback() 
* @throws SQLException 
*/  
public void rollback() throws SQLException {  
  if (connection != null && !connection.getAutoCommit()) {  
      if (log.isDebugEnabled()) {  
          log.debug("Rolling back JDBC Connection [" + connection + "]");  
      }  
      connection.rollback();  
  }  
}
```

## 3.3 ManagedTransaction

ManagedTransaction让容器来管理事务Transaction的整个生命周期，意思就是说，使用ManagedTransaction的commit和rollback功能不会对事务有任何的影响，它什么都不会做，它将事务管理的权利移交给了容器来实现。

 
```
public void commit() throws SQLException {  
  // Does nothing  
}  
 
public void rollback() throws SQLException {  
  // Does nothing  
}
```

如果我们使用MyBatis构建本地程序，即不是WEB程序，若将type设置成"MANAGED"，那么，我们执行的任何update操作，即使我们最后执行了commit操作，数据也不会保留，不会对数据库造成任何影响。因为我们将MyBatis配置成了“MANAGED”，即MyBatis自己不管理事务，而我们又是运行的本地程序，没有事务管理功能，所以对数据库的update操作都是无效的。
 
# 参考
- [终结篇：MyBatis原理深入解析（二）](https://www.jianshu.com/p/9e397d5c85fd)
- Mybatis源码

