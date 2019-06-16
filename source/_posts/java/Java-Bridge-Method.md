title: Java Bridge Method详解
date: 2018-02-15 15:47:44
description: 今天看Mybatis源码的时候，发现源码中有一个判断method是否是bridge。这个代码是github上开发人员提出的一个bug。mybatis针对该内容作了修改。之前没有接触过这个概念，所以上网搜了下，了解下Bridge Method。
categories: Java
tags:
    - Java
---

# 一. 背景

今天看Mybatis源码的时候，发现源码中有一个判断method是否是bridge。这个代码是github上开发人员提出的一个bug。mybatis针对该内容作了修改。之前没有接触过这个概念，所以上网搜了下，了解下Bridge Method。

Mybatis在解析和注册mapper的时候，代码里有这一段：

```
// issue #237
if (!method.isBridge()) {
    parseStatement(method);
}
```

github 该问题地址：https://github.com/mybatis/mybatis-3/issues/237
该问题java版本问题，如果定义了一个mapper接口BaseMapper, 另外在定义一个mapper接口MyModelMapper。 如果MyModelMapper中覆盖了BaseMapper中的方法，并且增加了一些注解。那么在Mybatis 编译的时候会报下面的错误:

```
Error while adding the mapper 'interface MyMapper' to configuration.
java.lang.IllegalArgumentException: Mapped Statements collection already contains value for MyMapper.insert!selectKey
```

我们看看具体的实例和原因：

```
public class GenericTest 
{
    @Target(METHOD)
    @Retention(RetentionPolicy.RUNTIME)
    public @interface BogusMyBatisSqlAnnotation {
    }

    public class MyModel {
    }

    // 基础类
    public interface BaseMapper<M> {
        public void insert(M model);
    }
    
    // 子类
    public interface MyModelMapper extends BaseMapper<MyModel> {
        @BogusMyBatisSqlAnnotation
        @Override
        public void insert(MyModel model);
    }

    public static void main( String[] args )
    {
        // 查看各个方法
        printMethodList(MyModelMapper.class);
    }

    public static void printMethodList(Class<?> clazz) {
        System.out.println();
        System.out.println(clazz.getSimpleName());
        Method[] interfaceMethods = clazz.getMethods();
        for (Method method : interfaceMethods) {
            System.out.println("  " + method);
            System.out.println("    isSynthetic = " + method.isSynthetic() + ", isBridge = " + method.isBridge());
            if (method.getAnnotations().length > 0) {
                for (Annotation annotation : method.getAnnotations()) {
                    System.out.println("    Annotation = " + annotation);
                }
            } else {
                System.out.println("    NO ANNOTATIONS!");
            }
            System.out.println();
        }
    }
}
```

使用java 1.7 编译的时候产生结果是:
```
MyModelMapper
  public abstract void GenericTest$MyModelMapper.insert(GenericTest$MyModel)
    isSynthetic = false, isBridge = false
    Annotation = @GenericTest$BogusMyBatisSqlAnnotation()

  public abstract void GenericTest$BaseMapper.insert(java.lang.Object)
    isSynthetic = false, isBridge = false
    NO ANNOTATIONS!
```

从结果上方法对应的类的全限定名是不同的，并且isBridge = false。 MyBatis正是通过这种方法遍历方式来解析和注册mapper。 因为GenericTest$MyModelMapper.insert和 GenericTest$BaseMapper.insert是不同的内容，因为两个都被注册进去。不会报错。

但是java 1.8就有问题了，其运行结果如下:
```
MyModelMapper
  public abstract void GenericTest$MyModelMapper.insert(GenericTest$MyModel)
    isSynthetic = false, isBridge = false
    Annotation = @GenericTest$BogusMyBatisSqlAnnotation()
    
  public default void GenericTest$MyModelMapper.insert(java.lang.Object)
    isSynthetic = true, isBridge = true
    Annotation = @GenericTest$BogusMyBatisSqlAnnotation()
```
我们发现，这两个方法全限定名都是一样的，都是GenericTest$MyModelMapper.insert。只是父类的方法使用了isBridge = true。 

因此如果Mybatis通过遍历Class的所有method，进行注入是，就会报上面的错误。最后Mybatis代码通过判断是否是bridge来避免重复注册。

说了这么多那什么是 bridge方法呢？

# 二. Bridge method

桥接方法是 JDK 1.5 引入泛型后，为了使Java的泛型方法生成的字节码和 1.5 版本前的字节码相兼容，由编译器自动生成的方法。

我们可以通过Method.isBridge()方法来判断一个方法是否是桥接方法，在字节码中桥接方法会被标记为ACC_BRIDGE和ACC_SYNTHETIC，其中ACC_BRIDGE用于说明这个方法是由编译生成的桥接方法，ACC_SYNTHETIC说明这个方法是由编译器生成，并且不会在源代码中出现。可以查看jvm规范中对这两个access_flag的解释http://docs.oracle.com/javase/specs/jvms/se7/html/jvms-4.html#jvms-4.6。


> 桥接方法是什么？
> 如果一个类继承了一个范型类或者实现了一个范型接口, 那么编译器在编译这个类的时候就会生成一个叫做桥接方法的混合方法(混合方法简单的说就是由编译器生成的方法, 方法上有synthetic修饰符), 这个方法用于范型的类型安全处理, 用户一般不需要关心桥接方法. 详细参考：[JSL bridge method](https://docs.oracle.com/javase/tutorial/java/generics/bridgeMethods.html#bridgeMethods)

如上面例子的父类方法：

```
public default void GenericTest$MyModelMapper.insert(java.lang.Object)
    isSynthetic = true, isBridge = true
    Annotation = @GenericTest$BogusMyBatisSqlAnnotation()

```

## 2.1 什么时候会生成桥接方法
那什么时候编译器会生成桥接方法呢？可以查看JLS中的描述: [JLS](http://docs.oracle.com/javase/specs/jls/se7/html/jls-15.html#jls-15.12.4.5)。

为了描述，何时产生Bridge我们定义一下两个类：

```
// 父类
public interface SuperClass<T> {  
    T method(T param);  
}  

// 子类
public class SubClass implements SuperClass<String> { 
    @Override 
    public String method(String param) {  
        return param;  
    }  
}  
```

我们看看SubClass的字节码：

```
public class com.mikan.SubClass implements com.mikan.SuperClass<java.lang.String> {  
  public com.mikan.SubClass();  
    flags: ACC_PUBLIC  
    Code:  
      stack=1, locals=1, args_size=1  
         0: aload_0  
         1: invokespecial #1                  // Method java/lang/Object."<init>":()V  
         4: return  
      LineNumberTable:  
        line 7: 0  
      LocalVariableTable:  
        Start  Length  Slot  Name   Signature  
               0       5     0  this   Lcom/mikan/SubClass;  
  
  public java.lang.String method(java.lang.String);  
    flags: ACC_PUBLIC  
    Code:  
      stack=1, locals=2, args_size=2  
         0: aload_1  
         1: areturn  
      LineNumberTable:  
        line 11: 0  
      LocalVariableTable:  
        Start  Length  Slot  Name   Signature  
               0       2     0  this   Lcom/mikan/SubClass;  
               0       2     1 param   Ljava/lang/String;  
  
  public java.lang.Object method(java.lang.Object);  
    flags: ACC_PUBLIC, ACC_BRIDGE, ACC_SYNTHETIC  
    Code:  
      stack=2, locals=2, args_size=2  
         0: aload_0  
         1: aload_1  
         2: checkcast     #2                  // class java/lang/String  
         5: invokevirtual #3                  // Method method:(Ljava/lang/String;)Ljava/lang/String;  
         8: areturn  
      LineNumberTable:  
        line 7: 0  
      LocalVariableTable:  
        Start  Length  Slot  Name   Signature  
               0       9     0  this   Lcom/mikan/SubClass;  
               0       9     1    x0   Ljava/lang/Object;  
}  
```

SubClass只声明了一个方法，而从字节码可以看到有三个方法:

 - 第一个是无参的构造方法（代码中虽然没有明确声明，但是编译器会自动生成)
 - 第二个是我们实现的接口中的方法
 - 第三个就是编译器自动生成的桥接方法。可以看到flags包括了ACC_BRIDGE和ACC_SYNTHETIC，表示是编译器自动生成的方法，参数类型和返回值类型都是Object。再看这个方法的字节码，它把Object类型的参数强制转换成了String类型，再调用在SubClass类中声明的方法，转换过来其实就是：
 
 ```
 public Object method(Object param) {  
    return this.method(((String) param));  
} 
 ```
 
 也就是说，桥接方法实际是是调用了实际的泛型方法。来看看下面的测试代码：
 ```
 public class BridgeMethodTest {  
    public static void main(String[] args) throws Exception {  
        SuperClass superClass = new SubClass();  
        System.out.println(superClass.method("abc123"));// 调用的是实际的方法  
        System.out.println(superClass.method(new Object()));// 调用的是桥接方法, 运行时检查参数和子类参数不一致，则会抛出异常
    }  
} 
```



## 2.2 为什么要生成桥接方法
**简单来说, 编译器生成bridge method的目的就是为了和jdk1.5之前的字节码兼容. 通过**因为范型是在jdk1.5之后才引入的. 在jdk1.5之前例如集合的操作都是没有范型支持的, 所以生成的字节码中参数都是用Object接收的, 所以也可以往集合中放入任意类型的对象, 集合类型的校验也被拖到运行期.

但是在jdk1.5之后引入了范型, 因此集合的内容校验被提前到了编译期, 但是为了兼容jdk1.5之前的版本java使用了范型擦除, 所以如果不生成桥接方法就和jdk1.5之前的字节码不兼容了.


Java的泛型是要擦除的，到了虚拟机泛型就变成了Object， 编码以后SuperClass对应编码是:
```
public interface com.mikan.SuperClass<T extends java.lang.Object>  
  Signature: #7                           // <T:Ljava/lang/Object;>Ljava/lang/Object;  
  SourceFile: "SuperClass.java"  
  minor version: 0  
  major version: 51  
  flags: ACC_PUBLIC, ACC_INTERFACE, ACC_ABSTRACT  
Constant pool:  
   #1 = Class              #10            //  com/mikan/SuperClass  
   #2 = Class              #11            //  java/lang/Object  
   #3 = Utf8               method  
   #4 = Utf8               (Ljava/lang/Object;)Ljava/lang/Object;  
   #5 = Utf8               Signature  
   #6 = Utf8               (TT;)TT;  
   #7 = Utf8               <T:Ljava/lang/Object;>Ljava/lang/Object;  
   #8 = Utf8               SourceFile  
   #9 = Utf8               SuperClass.java  
  #10 = Utf8               com/mikan/SuperClass  
  #11 = Utf8               java/lang/Object  
{  
  public abstract T method(T);  
    flags: ACC_PUBLIC, ACC_ABSTRACT  
    Signature: #6                           // (TT;)TT;  
}  
localhost:mikan mikan$  
```

对应的结果是:

```
// 父类
public interface SuperClass<T> {  
    Object method(Object param);  
}  
```

按照接口定义，必须实现接口中的所有方法。但是JVM发现，子类中只有一个方法：

```
public class SubClass implements SuperClass<String> { 
    @Override 
    public String method(String param) {  
        return param;  
    }  
} 
```

发现根本就没有实现父类的Object method(Object param)方法，为了兼容1.5之前版本，JVM在SubClass编译后的字节码上增加了桥接方法，用于实现父类方法。该方法实质上还是调用了public String method(String param)：

```
public java.lang.String method(java.lang.String);  
    flags: ACC_PUBLIC  
    Code:  
      stack=1, locals=2, args_size=2  
         0: aload_1  
         1: areturn  
      LineNumberTable:  
        line 11: 0  
      LocalVariableTable:  
        Start  Length  Slot  Name   Signature  
               0       2     0  this   Lcom/mikan/SubClass;  
               0       2     1 param   Ljava/lang/String;  
```


# 参考

- [Java Bridge Method 详解](https://www.jianshu.com/p/250030ea9b28)
- [JSL bridge method](https://docs.oracle.com/javase/tutorial/java/generics/bridgeMethods.html#bridgeMethods)
- [如何利用JClassLib修改.class文件](http://blog.csdn.net/betterandroid/article/details/14520667)
- [java中什么是bridge method（桥接方法）](http://blog.csdn.net/zghwaicsdn/article/details/50717334)
- [Java反射中method.isBridge()由来,含义和使用场景?](https://www.zhihu.com/question/54895701)





