title: Mybatis源码解析(2)--初始化
layout: post
date: 2018-02-14 12:12:43
comments: true
categories: Mybatis源码解析
tags: 
    - 源码解析
    - Mybatis
    
keywords: “Mybatis”
description: 在使用mybatis, spring等开源框架的时候,首先需要根据业务需求设置mybatis的配置，如数据源、mapper映射关系等。本文根据Mybatis源码介绍Mybatis如何完成初始化工作。

---

# 一. 介绍
在使用mybatis，spring等开源框架的时候，首先需要根据业务需求设置mybatis的配置，如: 数据源、mapper映射关系等。mybatis的配置包含两个大方面：
 1. configuration配置
 2. mapper配置


## 1.1 configuration配置
configuration主要提供了mybatis的主要配置，主要包括以下几个方面：

-  **environments环境**:
   - environment 环境变量
   - transactionManager 事物管理器
   - dataSource 数据源   
- **properties属性**： 
- **setting属性**:
- **typeAlias命名**:
- **typeHandlers类型处理器**
- **objectFactory对象工厂**
- **plugins插件**

### 1.1.1 environments
MyBatis 支持配置多个dataSource环境, 可以通过environments来配置多个环境的数据源、事物管理器TransactionManager、SqlSessionFactory等。

### 1.1.2 properties
属性配置元素可以将配置值具体化到一个属性文件中，并且使用属性文件的 key 名作为占位符。一般在开发中我们会将数据库配置的信息存放在application.properties文件中。通过该配置可以获取属性配置元素，并通过占位符方式设置到mybatis配置文件中。

### 1.1.3 typeAliases 类型别名
SQLMapper 配置文件中，对于 resultType 和 parameterType 属性值，我们需要使用 JavaBean 的完全限定名。我们可以通过typeAliases为这些全限定名取一个别名，可以简化开发过程。

### 1.1.4 typeHandlers 类型处理器
当 MyBatis 将一个 Java 对象作为输入参数执行 INSERT 语句操作时，它会创建一个 PreparedStatement 对象，并且 使用 setXXX()方式对占位符设置相应的参数值。这里，XXX 可以是 Int，String，Date 等 Java 对象属性类型的任意一个。MyBatis 对于以下的类型使用内建的类型处理器:所有的基本数据类型、基本类型的包裹类型、byte[]、 java.util.Date、java.sql.Date、java.sql.Time、java.sql.Timestamp、java 枚举类型等。

如果不是这些内建类型应该如何处理呢？mybatis为我们提供了typeHandlers类型处理器，让我们去指定位置类型的处理方式。当遇到该类型值时，则调用对应的typeHandlers进行处理。

### 1.1.5 全局参数设置 Settings
这里主要是设置mybatis的一些控制变量，通过settings可以对一些参数做修改，覆盖MyBatis 默认的全局参数设置。如：
```
<settings>
    <setting name="lazyLoadingEnabled" value="true" />
</settings>
```

## 1.2 mapper配置
mapper主要配置sql语句与java mapper对象之间的关系。Mapper XML中的每个SQL语句都会定义一个唯一的statement ID，即对应java mapper对象的方法和参数的组合。 当我们需要执行mapper对应的方法时(statement ID)，就会解析调用对应的SQL语句。


# 二. 源码实现
Mybatis中提供了Configuration对象来存储这些配置信息，Configuration类保存了所有Mybatis的配置信息,如mybaits-config.xml和Student.xml中的所有配置信息都会存放在Configuration。一般情况下Mybatis在运行过程中只会创建一个Configration对象，并且配置信息不能再被修改。

在执行数据操作时，首先会从这个Configuration中获取相关的配置信息，然后执行。mybatis提供了两种配置方式：

1. 基于xml的配置: 基于XML配置文件的方式是将MyBatis的所有配置信息放在XML文件中，MyBatis通过加载并XML配置文件，将配置文信息组装成内部的Configuration对象。
2. 基于java api的配置: 使用java代码手动创建Configuration，后将配置参数set 进入Configuration对象中。

xml配置的方式本质上还是和java api配置方式一致，只是多了一些xml的解析过程。本文主要讨论mybatis如何通过读取xml文件来初始化Mybatis，初始化Configuration。

## 2.1 切入点
为了看源码如何执行加载，我们需要找到一个切入口，通过该切入口进行跟进。首先根据官网的文档,我们可以快速创建一个简单的demo完成以下工作：


```
String resource = "mybatis-config.xml";  
InputStream inputStream = Resources.getResourceAsStream(resource);  
// mybatis初始化 
SqlSessionFactory sqlSessionFactory = new SqlSessionFactoryBuilder().build(inputStream);  

// 创建SqlSession
SqlSession sqlSession = sqlSessionFactory.openSession();

StudentMapper studentMapper = sqlSession.getMapper(StudentMapper.class);
// 执行SQL语句
Student student = studentMapper.findStudentById(1);
```

上述代码的功能：
1. mybatis初始化, 根据配置文件mybatis-config.xml 配置文件，创建SqlSessionFactory对象。
2. 创建SqlSession
3. 执行SQL语句

mybatis的初始化动作主要发生在这句代码中：

```
SqlSessionFactory sqlSessionFactory = new SqlSessionFactoryBuilder().build(inputStream);  
```
接下来我们看看mybatis是如何完成初始化过程的。

## 2.2 MyBatis初始化基本过程
xml格式定义有两种，DTD和XSD. Mybatis 的xml配置采用了DTD格式，两者比较可以参考: [Spring源码学习--DTD和XML Schema介绍](http://zhengjianglong.cn/2015/12/06/docs/15182657110957/)

根据spring源码的阅读经验上看，mybatis的流程大概是：

1. Mybatis首先会将配置文件(mybatis-config.xml)转换IO流资源(Spring采用自己构建的一套Resource体系，而Mybatis采用的是Java内置的如InputSteam、Reader)
2. 检查IO流资源是否符合Mybatis的xml DTD规范。为了提高响应速度，避免联网验证，一般模块都会提供xml配置声明(DTD), 并实现entityResolver来验证。
3. 将IO流资源转换为Document。 
4. 对Document中的各个Node(properties、setting、environments等)进行解析，将内容存放到一个容器中--configuration。
5. 在Node中比较特殊的是mapper配置，如果mapper配置是resource类型，则读取mapper资源进行解析
5. 返回configuration


流程中的关键步骤就是将IO流资源转换为document, 然后document的node信息解析存放到Configuration中。Mybatis是如何实现的呢？针对mybatis-config.xml配置文件和Mapper配置文件，Mybatis由两个相对应的类来解析的:

 - XMLConfigBuilder解析mybatis-config.xml的配置到Configuration中， xml的解析交给了XPathParser， xml的格式验证交给XMLMapperEntityResolver处理。
 - XMLMapperBuilder 解析Mapper配置文件的配置到Configuration中


 根据源码，mybatis的解析过程如下图所示：
 ![mybatis](/images/mybatis.jpg)

如上图所示,Mybatis的主要逻辑是：
1. 将mybatis-config.xml包装为Reader或InputStream
2. 将inputStream对象交给SqlSessionFactoryBuilder
3. SqlSessionFactoryBuilder调用XMLConfigBuilder对象的parse()方法；
4. SqlSessionFactoryBuilder根据Configuration对象创建一个DefaultSessionFactory对象；


SqlSessionFactoryBuilder相关代码如下：

```
public SqlSessionFactory build(InputStream inputStream)  {  
      return build(inputStream, null, null);  
}  

public SqlSessionFactory build(InputStream inputStream, String environment, Properties properties)  {  
      try  {  
          //2. 创建XMLConfigBuilder对象用来解析XML配置文件，生成Configuration对象  
          XMLConfigBuilder parser = new XMLConfigBuilder(inputStream, environment, properties);  
          //3. 将XML配置文件内的信息解析成Java对象Configuration对象  
          Configuration config = parser.parse();  
          //4. 根据Configuration对象创建出SqlSessionFactory对象  
          return build(config);  
      } catch (Exception e) {  
          throw ExceptionFactory.wrapException("Error building SqlSession.", e);  
      } finally {  
          ErrorContext.instance().reset();  
          try {  
              inputStream.close();  
          } catch (IOException e) {  
              // Intentionally ignore. Prefer previous error.  
          }  
      }
}

// 从此处可以看出，MyBatis内部通过Configuration对象来创建SqlSessionFactory,用户也可以自己通过API构造好Configuration对象，调用此方法创SqlSessionFactory  
public SqlSessionFactory build(Configuration config) {  
      return new DefaultSqlSessionFactory(config);  
}
```

mybatis初始化过程中涉及到以下几个重要的类：

 - SqlSessionFactoryBuilder： SqlSessionFactory的构造器，用于创建SqlSessionFactory，采用了Builder设计模式
 - Configuration: 如上面所介绍，主要是存储mybatis的所有配置信息
 - SqlSessionFactory: SqlSession工厂类，以工厂形式创建SqlSession对象，采用了Factory工厂设计模式
 - XmlConfigParser: 解析mybatis-config.xml的配置到Configuration中
 - XMLMapperBuilder: 解析Mapper配置文件的配置到Configuration中
 - XPathParser：负责将IO流转换为Document,XmlConfigParser和XmlConfigParser都使用该类完成Document的创建、获取Node等
 - XMLMapperEntityResolver: 避免xml文件网络验证，提高效率，而实现的xml本地化验证器。根据Mybatis定义的dtd规范，验证xml的格式

## 2.3 XMLConfigBuilder
XMLConfigBuilder 在实例化的时候会创建XPathParser，并完成了IO流资源到Document的转换。

```
// XMLConfigBuilder 构造器
public XMLConfigBuilder(InputStream inputStream, String environment, Properties props) {
    /**
     * 创建一个解析器
     */
    this(new XPathParser(inputStream, true, props, new XMLMapperEntityResolver()), environment, props);
  }
  
  // XPathParser 构造器
  public XPathParser(InputStream inputStream, boolean validation, Properties variables, EntityResolver entityResolver) {
    commonConstructor(validation, variables, entityResolver);
    /**
     * 完成document的创建
     */
    this.document = createDocument(new InputSource(inputStream));
  }
```

XMLConfigBuilder在初始化的时候会创建一个XPathParser对象。而XPathParser初始化时将inputStream直接转换为Document.之后SqlSessionFactoryBuilder会调用XMLConfigBuilder的parse方法，完成对DOM中各个Node的解析，并将结果设置到Configuration

```
public Configuration parse() {
    // 防止重复调用
    if (parsed) {
      throw new BuilderException("Each XMLConfigBuilder can only be used once.");
    }
    parsed = true;
    // parser.evalNode("/configuration") 获取configuration的节点
    XNode configurationNode = parser.evalNode("/configuration");
    // 对Document 中的各节点进行解析
    parseConfiguration(configurationNode);
    return configuration;
  }
```

## 2.4 XPathParser
XPathParser 负责将xml配置文件转换为Document和XNode， mybatis-config.xml和StudentMapper.xml映射文件都是通过这个类处理、转换。XpathParser的作用是提供根据Xpath表达式获取基本的DOM节点Node信息的操作。

XPathParser主要由以下三个重要部分组成:
![](/images/15186013944163.jpg)

- Document
- EntityResovler: 验证和解析xml用，mybatis采用XMLMapperEntityResolver类完成相关逻辑
- XPath


XMLConfigBuilder会将XML配置文件的信息转换为Document对象，这里采用了DOM完成解析。
XML配置定义文件DTD转换成XMLMapperEntityResolver对象，通过XMLMapperEntityResolver和Xpath完成从Document中获取DOM节点Node信息的操作。


当XMLConfigBuilder调用parse()方法：会从XPathParser中取出 <configuration>节点对应的Node对象，然后解析此Node节点的子Node：


```
private void parseConfiguration(XNode root) {
    try {
      //issue #117 read properties first
      // 1.首先处理properties 节点
      propertiesElement(root.evalNode("properties"));
      // 2. 处理settings配置
      Properties settings = settingsAsProperties(root.evalNode("settings"));
      loadCustomVfs(settings);
      // 3. 处理类型命名 typeAliases
      typeAliasesElement(root.evalNode("typeAliases"));
      // 4. 处理插件配置
      pluginElement(root.evalNode("plugins"));
      // 5. 处理objectFactory
      objectFactoryElement(root.evalNode("objectFactory"));
      objectWrapperFactoryElement(root.evalNode("objectWrapperFactory"));
      reflectorFactoryElement(root.evalNode("reflectorFactory"));
      settingsElement(settings);
      // read it after objectFactory and objectWrapperFactory issue #631
      environmentsElement(root.evalNode("environments"));
      databaseIdProviderElement(root.evalNode("databaseIdProvider"));
      typeHandlerElement(root.evalNode("typeHandlers"));
      /**
       * 处理mappers
       */
      mapperElement(root.evalNode("mappers"));
    } catch (Exception e) {
      throw new BuilderException("Error parsing SQL Mapper Configuration. Cause: " + e, e);
    }
}
```

## 2.5 各Node的解析
### 2.5.1 environments 配置解析

### 2.5.2 typeAliases 配置解析
typeAliases的配置分为两种：1）基于package, Mybatis则会把这个package下的所有类都扫描，设置别名。2）根据全限定类名设置，Mybatis只要直接设置就可以。

通过package的设置代码如下：

```
public void registerAliases(String packageName, Class<?> superType){
    ResolverUtil<Class<?>> resolverUtil = new ResolverUtil<Class<?>>();
    resolverUtil.find(new ResolverUtil.IsA(superType), packageName);
    // 获取包下 所有的类
    Set<Class<? extends Class<?>>> typeSet = resolverUtil.getClasses();
    for(Class<?> type : typeSet){
      if (!type.isAnonymousClass() && !type.isInterface() && !type.isMemberClass()) {
        // 注册
        registerAlias(type);
      }
    }
  }
```

如果基于package或未指定alias时，Mybatis会优先使用@Alais的配置，如果不存在则再使用目标类的类名小写作为别名。相反如果xml设置了别名，那么Mybatis则有限考虑XML中的别名设置，而不考虑@Alias。

```
String alias = type.getSimpleName();
```

Mybatis的别名不区分大小写，所以在注册的时候会将别名alias先转化为小写。然后存放到configuration的TypeAliasRegistry属性的TYPE_ALIASES里。

Configuration在初始化的时候，默认会为一些类设置别名, 包括JDBC, JNDI,POOLED等。通过这些别名，Mybatis也可以简化用户的配置。具体如下：

```
public Configuration() {
    typeAliasRegistry.registerAlias("JDBC", JdbcTransactionFactory.class);
    typeAliasRegistry.registerAlias("MANAGED", ManagedTransactionFactory.class);

    typeAliasRegistry.registerAlias("JNDI", JndiDataSourceFactory.class);
    typeAliasRegistry.registerAlias("POOLED", PooledDataSourceFactory.class);
    typeAliasRegistry.registerAlias("UNPOOLED", UnpooledDataSourceFactory.class);

    typeAliasRegistry.registerAlias("PERPETUAL", PerpetualCache.class);
    typeAliasRegistry.registerAlias("FIFO", FifoCache.class);
    typeAliasRegistry.registerAlias("LRU", LruCache.class);
    typeAliasRegistry.registerAlias("SOFT", SoftCache.class);
    typeAliasRegistry.registerAlias("WEAK", WeakCache.class);

    typeAliasRegistry.registerAlias("DB_VENDOR", VendorDatabaseIdProvider.class);

    typeAliasRegistry.registerAlias("XML", XMLLanguageDriver.class);
    typeAliasRegistry.registerAlias("RAW", RawLanguageDriver.class);

    typeAliasRegistry.registerAlias("SLF4J", Slf4jImpl.class);
    typeAliasRegistry.registerAlias("COMMONS_LOGGING", JakartaCommonsLoggingImpl.class);
    typeAliasRegistry.registerAlias("LOG4J", Log4jImpl.class);
    typeAliasRegistry.registerAlias("LOG4J2", Log4j2Impl.class);
    typeAliasRegistry.registerAlias("JDK_LOGGING", Jdk14LoggingImpl.class);
    typeAliasRegistry.registerAlias("STDOUT_LOGGING", StdOutImpl.class);
    typeAliasRegistry.registerAlias("NO_LOGGING", NoLoggingImpl.class);

    typeAliasRegistry.registerAlias("CGLIB", CglibProxyFactory.class);
    typeAliasRegistry.registerAlias("JAVASSIST", JavassistProxyFactory.class);

    ...
}
```

## 2.6 mapper解析

Node中有个比较特别的Node,是mapper。 mapper如果是resource类型，则需要加载xml资源进行解析。将xml转换为document，再读取里面的Node点点一一解析，将解析结果存储到Configuration中。
```
mapperElement(root.evalNode("mappers"));
```
接下来我们将分析下Mapper的加载过程，Mybatis提供了两种方式配置mapper：
 - 注解方式配置。这种一般需要在xml配置文件中指明base package或class，Mybatis从这个包里获取所有的Mapper，并根据一些注解如@Insert等来构建SQL和statement ID的映射关系。
 - xml配置。xml配置文件的路径提供了两种方式，一个是指定resource即指定class路径下的具体问题。另一种是利用文件系统来指定url。

 因此，mybatis的配置信息包含以下四种:
  - package: 根据包去扫描获取
  - class：直接定位class，通过注解信息，解析mapper的配置。和package都属于注解配置方式。
  - resource： 指定classpath路径，根据该路径获取mapper的配置文件。
  - url: 指定文件系统路径，根据该路径获取mapper的文件配置。

### 2.6.1 xml配置mapper方式解析
首先都是根据路径(resource或url)获取资源文件，并转化为InputStream。 然后将inputSteam交给XMLMapperBuilder类进行解析，解析的结果存到Configuration中。和Mybatis-config.xml加载、解析过程一样，Mapper.xml文件首先通过XPathParser构建Document, 然后对Document中的接个Node进行解析。

```
InputStream inputStream = Resources.getUrlAsStream(url);
XMLMapperBuilder mapperParser = new XMLMapperBuilder(inputStream, configuration, url, configuration.getSqlFragments());
mapperParser.parse();
```
mapper映射文件中的配置包含三类:

1. ResultMaps 配置： 结果映射配置
2. cache 给定命名空间的缓存配置
3. cache-ref: 其他命名空间缓存配置的引用
2. Statements 配置: Statement ID和SQL的映射关系
3. sql 可被其他语句引用的可重用语句块。
4. statement（SELECT|UPDATE|DELETE|INSERT: 增删改查）解析

#### resultMap
根据myBatis的要求，从Node中解析以下信息:
 
 - constructor:  类在实例化时,用来注入结果到构造方法中
 - id: 一个 ID 结果;标记结果作为 ID 可以帮助提高整体效能
 - result: 注入到字段或 JavaBean 属性的普通结果
 - association: 一个复杂的类型关联;许多结果将包成这种类型
 - collection: 复杂类型的集
 - discriminator: 使用结果值来决定使用哪个结果映射
 
 解析属性值，无非判断Node节点类型，从中读取对应字段的值。对每一元素都会建一个ResultMaping来存储映射关系。最后将所有元素的ResultMapping都存放到ResultMap。ResultMap采用链表结构在存储这些ResultMaping, 查询的时候需要顺序查找。如果表属性比较多的话，影响性能。但一般情况下一个表的属性或字段不会太多，因此对性能影响可以忽略。ResultMap的存储结构如下：
 
 ```
 private String id;
  private Class<?> type;
  private List<ResultMapping> resultMappings;
  private List<ResultMapping> idResultMappings;
  private List<ResultMapping> constructorResultMappings;
  private List<ResultMapping> propertyResultMappings;
  private Set<String> mappedColumns;
  private Set<String> mappedProperties;
  private Discriminator discriminator;
  private boolean hasNestedResultMaps;
  private boolean hasNestedQueries;
  private Boolean autoMapping;
 ```
 
 全部解析完成后，会将构建好的ResultMap保存到configuration中。 Configuration.addResultMap代码：
 
 ```
 resultMaps.put(rm.getId(), rm);
 ...
 ```
 
 因此可以通过Id，就可以获取ResultMap对象。那么Id又是什么？一般在定义resultMap的时候都会设定一个id,作为该resultMap的唯一标识:
 ```
 <resultMap id="detailedBlogResultMap" type="Blog">
 ```
  
参考: http://www.mybatis.org/mybatis-3/zh/sqlmap-xml.html

#### statement解析
statement包含了INSERT、SELECT、DELETE、UPDATE这些具体SQL的配置，statement的解析是交给了XMLStatementBuilder来负责解析。

```
for (XNode context : list) {
      final XMLStatementBuilder statementParser = new XMLStatementBuilder(configuration, builderAssistant, context, requiredDatabaseId);
      try {
        statementParser.parseStatementNode();
      } catch (IncompleteElementException e) {
        configuration.addIncompleteStatement(statementParser);
      }
}
```

1. 首先获取Node中的各个元素值，如id, resultType、paramterMap等。
2. 利用LanguageDriver解析SQL语句，包含动态SQL语句。如果是动态SQL则解析完成用DynamicSqlSource类包装，反之采用RawSqlSource包装。
3. 动态SQL解析的时候会给每个动态标签设置一个Handler处理器，采用了策略模式，根据标签名字从map中获取对应的处理器。


不同标签对应的处理器：

```
private void initNodeHandlerMap() {
    nodeHandlerMap.put("trim", new TrimHandler());
    nodeHandlerMap.put("where", new WhereHandler());
    nodeHandlerMap.put("set", new SetHandler());
    nodeHandlerMap.put("foreach", new ForEachHandler());
    nodeHandlerMap.put("if", new IfHandler());
    nodeHandlerMap.put("choose", new ChooseHandler());
    nodeHandlerMap.put("when", new IfHandler());
    nodeHandlerMap.put("otherwise", new OtherwiseHandler());
    nodeHandlerMap.put("bind", new BindHandler());
  }
```

## 2.6 基于Java API手动加载XML配置文件
根据maybatis的源码，我们可以使用XMLConfigBuilder手动解析XML配置文件来创建Configuration对象，代码如下：
```
String resource = "mybatis-config.xml";  
InputStream inputStream = Resources.getResourceAsStream(resource);  
// 手动创建XMLConfigBuilder，并解析创建Configuration对象  
XMLConfigBuilder parser = new XMLConfigBuilder(inputStream, null,null);  
Configuration configuration=parse();  
// 使用Configuration对象创建SqlSessionFactory  
SqlSessionFactory sqlSessionFactory = new SqlSessionFactoryBuilder().build(configuration);  
// 使用MyBatis  
SqlSession sqlSession = sqlSessionFactory.openSession();  
StudentMapper studentMapper = sqlSession.getMapper(StudentMapper.class);
// 执行SQL语句
Student student = studentMapper.findStudentById(1);
```


# 参考
[1] [ashan的maybatis系列](http://blog.csdn.net/ashan_li/article/list)
[2] [dtd声明和entityResolver避免saxReader联网验证](http://blog.csdn.net/jie1336950707/article/details/48956727)
[3] [四种生成和解析XML文档的方法详解（介绍+优缺点比较+示例）](https://www.cnblogs.com/lanxuezaipiao/archive/2013/05/17/3082949.html)




