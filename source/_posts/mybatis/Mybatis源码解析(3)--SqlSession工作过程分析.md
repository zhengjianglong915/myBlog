title: Mybatis源码解析(3)--SqlSession工作过程分析
layout: post
date: 2018-02-15 13:33:09
comments: true
categories: Mybatis源码解析
tags: 
    - 源码解析
    - Mybatis
    
keywords: “Mybatis”
description: 上一篇博客从源码角度已经分析了Mybatis如何加载配置，如何通过配置完成Configuration的初始化工作，已经如何获得SqlSession。本文主要是分析SqlSession如何执行SQL操作。

---

# 一. 介绍
传统的Mybatis进行SqlSession操作的时候，是通过传递statement ID和参数给sqlSession对象，sqlSession完成数据库操作。如图所示:
![传统的Mybatis工作模式](/images/15186760903514.jpg)

为了考虑面向对象编程等原因，Mybatis提供了Mapper配置。根据MyBatis 的配置规范配置好后，通过SqlSession.getMapper(XXXMapper.class)方法，MyBatis 会根据相应的接口声明的方法信息，通过动态代理机制生成一个Mapper 实例，我们使用Mapper接口的某一个方法时，MyBatis会根据这个方法的方法名和参数类型，确定Statement Id，底层还是通过SqlSession.select("statementId",parameterObject);或者SqlSession.update("statementId",parameterObject); 等等来实现对数据库的操作，MyBatis引用Mapper 接口这种调用方式，纯粹是为了满足面向接口编程的需要。（其实还有一个原因是在于，面向接口的编程，使得用户在接口上可以使用注解来配置SQL语句，这样就可以脱离XML配置文件，实现“0配置”）


# 二. 源码实现
Mybatis的数据库访问会话都是交给sqlSession对象,  sqlSession对象封装了数据库访问，实现事务的控制和数据查询，简化数据库操作。

![](/images/15186769004537.jpg)

## 2.1 开启一个数据库访问会话---创建SqlSession对象
在使用SqlSession的时候需要先开启一个数据库访问会话。上一篇我们已经接受如何获得SqlSession，这里不再详细描述。

```
SqlSession sqlSession = factory.openSession(); 
```

## 2.2 执行sql操作的两种方式
Mybatis提供了两种方式执行操作：

1. 通过传递statement ID和参数，给SqlSession对象，来完成对应的数据库操作。
如：
```
Student student = sqlSession.selectOne("cn.zhengjianglong.ssmdemo.entity.mapper.StudentMapper.findStudentById",params);
```

2. 通过调用对应的Mapper接口来完成。这种方式的本质是创建了一个代理对象，底层也是采用第一种方式。只是通过代理提供一层包装，同时使得Mybatis具有面向对象思维。如：
```
StudentMapper studentMapper = sqlSession.getMapper(StudentMapper.class);
Student student = studentMapper.findStudentById(studId);
```

两者本质上都一直，而平日里大部分使用的都是Mapper对象方式，因此本文主要介绍基于Mapper对象的sql执行方式。

## 2.3 代理构建

Mapper都是接口实现，Mybatis如何完成动态代理
```
StudentMapper studentMapper = sqlSession.getMapper(StudentMapper.class);
```
sqlSession 默认是采用DefaultSqlSession，因此该操作实际上是DefaultSqlSession在执行。在初始化的时候Mybatis会将配置中的mapper等信息及对应的代理生成工厂存放到configuration中。DefaultSqlSession带代理的获得交给DefaultSqlSession处理。
最后Configuration将获取代理对象的工作交个了MapperRegistry：

```
 public <T> T getMapper(Class<T> type, SqlSession sqlSession) {
    // 获取Mapper代理对象工厂
    final MapperProxyFactory<T> mapperProxyFactory = (MapperProxyFactory<T>) knownMappers.get(type);
    if (mapperProxyFactory == null) {
      throw new BindingException("Type " + type + " is not known to the MapperRegistry.");
    }
    try {
      // 创建一个代理对象
      return mapperProxyFactory.newInstance(sqlSession);
    } catch (Exception e) {
      throw new BindingException("Error getting mapper instance. Cause: " + e, e);
    }
}
```

那MapperProxyFactory是何时设置到configuration的呢？在Mybatis的mapper文件解析的时候有这段代码:

```
public void parse() {
    // 若当前Mapper.xml尚未加载，则加载
    if (!configuration.isResourceLoaded(resource)) {
      // 解析<mapper>节点
      configurationElement(parser.evalNode("/mapper"));

      // 将当前Mapper.xml标注为『已加载』（下回就不用再加载了）
      configuration.addLoadedResource(resource);

      // 【关键】将Mapper Class添加至Configuration中
      bindMapperForNamespace();
    }

    // ResultMaps 解析
    parsePendingResultMaps();
    // 缓存
    parsePendingCacheRefs();
    // Statements 解析
    parsePendingStatements();
  }
```

在bindMapperForNamespace方法的时候，就完成了这些注册操作。进入方法内部, 下面这个部分完成代理工厂的注册：
```
/**
 * 创建一个代理工厂，并保存到knownMappers中
 */
knownMappers.put(type, new MapperProxyFactory<T>(type));
```

获得代理工厂以后，是如何生成Mapper代理对象的呢？Mybatis采用了java的Proxy来完成动态代理构建。

```
@SuppressWarnings("unchecked")
protected T newInstance(MapperProxy<T> mapperProxy) {
return (T) Proxy.newProxyInstance(mapperInterface.getClassLoader(), new Class[] { mapperInterface }, mapperProxy);
}

public T newInstance(SqlSession sqlSession) {
/**
 * 代理对象，对每个方法进行代理
 */
final MapperProxy<T> mapperProxy = new MapperProxy<T>(sqlSession, mapperInterface, methodCache);
return newInstance(mapperProxy);
}
```

创建了一个MapperProxy代理对象，会将所有的方法都交给MapperProxy的invoke完成。通过这个方法来实现SQL的操作等。Mybatis对每一次调用都会为namespace创建一个新的代理对象，没有采用缓存机制来存储。这样设计的不足是如果频繁调用mapper中的不同操作时，就会创建多个代理对象，影响性能。如果和Spring结合使用可以避免这块的问题
 
`为什么这么设计？`

## 2.4 执行sql调用

```
Student student = studentMapper.findStudentById(studId);
```

在执行以上方法的时候，实际上执行了代理对象MapperProxy的invoke方法。Mybatis会为每个方法，都定义一个MapperMethod。MapperMethod是真正负责sql的地方，在这边我们会看到mybatis如何根据statementId和参数与数据库进行会话。为了避免重复构建，在MapperProxyFactory提供了一个缓冲，用来存放每一个已经创建的MapperMethod。为了保住线程安全缓冲采用的是ConcurrentHashMap。

```
private MapperMethod cachedMapperMethod(Method method) {
    MapperMethod mapperMethod = methodCache.get(method);
    if (mapperMethod == null) {
      // 如果缓存没有则构建一个
      mapperMethod = new MapperMethod(mapperInterface, method, sqlSession.getConfiguration());
      methodCache.put(method, mapperMethod);
    }
    return mapperMethod;
}
```

获得MapperMethod以后就执行了MapperMethod的execute方法:

```
public Object execute(SqlSession sqlSession, Object[] args) {
    Object result;
    switch (command.getType()) {
        
      ...
      case SELECT:
          ... 
          // 和之前前面说的另一种方式一致
         Object param = method.convertArgsToSqlCommandParam(args);
          result = sqlSession.selectOne(command.getName(), param);
      ...

      return result;
  }
```

这边代码有些多，删除了一部分。该方法主要根据命令类型来选择对应的操作。上面的案例是执行查询操作，从代码可以看出这部分和我们之前说的另一种执行方式是一致的。两个方法在这里总于走到了一块了。

selectOne操作是selectList的一种特殊情况，所以selectOne方法内部调用了selectList，将查询的数量设置为1. 

```
// 获取MappedStatement
MappedStatement ms = configuration.getMappedStatement(statement);

// 交给executor 执行
return executor.query(ms, wrapCollection(parameter), rowBounds, Executor.NO_RESULT_HANDLER);
```

上一篇文章已经说了初始化过程。Mybatis会将StudentMapper.xml 加载到内存中会生成一个对应的MappedStatement对象，然后会以key="cn.zhengjianglong.sshdemo.entity.mapper.StudentMapper.findStudentById" ，value为MappedStatement对象的形式维护到Configuration的一个Map中。当以后需要使用的时候，只需要通过Id值来获取就可以了。


Executor是MyBatis执行器，是MyBatis调度的核心，负责SQL语句的生成和查询缓存的维护；MyBatis执行器Executor根据SqlSession传递的参数执行query()方法。

## 2.5 Excutor执行

excutor会根据根据具体传入的参数，动态地生成需要执行的SQL语句，用BoundSql对象表示。
完成一次sql执行操作，需要建立数据库会话和网路传输等。为了提高性能，Mybatis内部提供了一级缓存和二级缓存。因此在执行的时候会先构建key, 根据key先查看缓存中是否有对应的结果值。如果有就不用去执行操作了，直接把结果返回。
                                
```
public <E> List<E> query(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler) throws SQLException {
      // 1. 根据具体传入的参数，动态地生成需要执行的SQL语句，用BoundSql对象表示    
      BoundSql boundSql = ms.getBoundSql(parameter);  
      // 2. 为当前的  查询创建一个缓存Key  
      CacheKey key = createCacheKey(ms, parameter, rowBounds, boundSql);  
      return query(ms, parameter, rowBounds, resultHandler, key, boundSql);  
}  
```

qury中主要逻辑是，根据key从缓存中取出结果，如果结果是缓存没有，则从数据库读取，并将结果存放到缓存中。主要代码逻辑如下：

```
list = resultHandler == null ? (List<E>) localCache.getObject(key) : null;
if (list != null) {  
    handleLocallyCachedOutputParameters(ms, key, parameter, boundSql);  
} else {  
    // 3.缓存中没有值，直接从数据库中读取数据    
    list = queryFromDatabase(ms, parameter, rowBounds, resultHandler, key, boundSql);  
 }  
```

Executor.query()方法几经转折，最后会创建一个StatementHandler对象，然后将必要的参数传递给StatementHandler，使用StatementHandler来完成对数据库的查询，最终返回List结果集。

```
/** 
   * 
   * SimpleExecutor类的doQuery()方法实现 
   * 
   */  
public <E> List<E> doQuery(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler, BoundSql boundSql) throws SQLException {  
      Statement stmt = null;  
      try {  
          Configuration configuration = ms.getConfiguration();  
          //5. 根据既有的参数，创建StatementHandler对象来执行查询操作  
          StatementHandler handler = configuration.newStatementHandler(wrapper, ms, parameter, rowBounds, resultHandler, boundSql);  
          //6. 创建java.Sql.Statement对象，传递给StatementHandler对象  
          stmt = prepareStatement(handler, ms.getStatementLog());  
          //7. 调用StatementHandler.query()方法，返回List结果集  
          return handler.<E>query(stmt, resultHandler);  
       } finally {  
           closeStatement(stmt);  
       }  
}
```

从上面的代码中我们可以看出，Executor的功能和作用是：
 1. 根据传递的参数，完成SQL语句的动态解析，生成BoundSql对象，供StatementHandler使用；
 2. 为查询创建缓存，以提高性能；
 3. 创建JDBC的Statement连接对象，传递给StatementHandler对象，返回List查询结果；


## 2.6 StatementHandler

StatementHandler对象负责设置Statement对象中的查询参数、处理JDBC返回的resultSet，将resultSet加工为List 集合返回：

```
/** 
   * 
   * SimpleExecutor类的doQuery()方法实现 
   * 
   */  
@Override
  public <E> List<E> doQuery(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler, BoundSql boundSql) throws SQLException {
    Statement stmt = null;
    try {
      Configuration configuration = ms.getConfiguration();
      // 1. 根据既有的参数，创建StatementHandler对象来执行查询操作
      StatementHandler handler = configuration.newStatementHandler(wrapper, ms, parameter, rowBounds, resultHandler, boundSql);

      // 2. 创建java.Sql.Statement对象，传递给StatementHandler对象
      stmt = prepareStatement(handler, ms.getStatementLog());

      // 3. 调用StatementHandler.query()方法，返回List结果集
      return handler.<E>query(stmt, resultHandler);
    } finally {
      closeStatement(stmt);
    }
  }
 
private Statement prepareStatement(StatementHandler handler, Log statementLog) throws SQLException {
      Statement stmt;  
      Connection connection = getConnection(statementLog);  
      stmt = handler.prepare(connection);  
      //对创建的Statement对象设置参数，即设置SQL 语句中 ? 设置为指定的参数  
      handler.parameterize(stmt);  
      return stmt;  
}
```

StatementHandler对象主要完成4个工作：
 - 根据既有的参数，创建StatementHandler对象来执行查询操作
 - 创建java.Sql.Statement对象，传递给StatementHandler对象
 - 对创建的Statement对象设置参数，即设置SQL 语句中 ? 设置为指定的参数 
 - 调用StatementHandler.query()方法，返回List结果集



 StatementHandler的parameterize(Statement) 方法调用了 ParameterHandler的setParameters(statement) 方法，
ParameterHandler的setParameters(Statement)方法负责 根据我们输入的参数，对statement对象的 ? 占位符处进行赋值。

```

Object value;
  String propertyName = parameterMapping.getProperty();
  if (boundSql.hasAdditionalParameter(propertyName)) { // issue #448 ask first for additional params
    value = boundSql.getAdditionalParameter(propertyName);
  } else if (parameterObject == null) {
    value = null;
  } else if (typeHandlerRegistry.hasTypeHandler(parameterObject.getClass())) {
    value = parameterObject;
  } else {
    MetaObject metaObject = configuration.newMetaObject(parameterObject);
    value = metaObject.getValue(propertyName);
  }
  TypeHandler typeHandler = parameterMapping.getTypeHandler();
  JdbcType jdbcType = parameterMapping.getJdbcType();
  if (value == null && jdbcType == null) {
    jdbcType = configuration.getJdbcTypeForNull();
  }
  
 // 设置参数值  
 typeHandler.setParameter(ps, i + 1, value, jdbcType);
```

# 参考
 - [终结篇：MyBatis原理深入解析（一）](https://www.jianshu.com/p/ec40a82cae28)





