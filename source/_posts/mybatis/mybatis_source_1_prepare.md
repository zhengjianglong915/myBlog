
title: Mybatis源码解析(1)--准备
layout: post
date: 2018-02-14 10:27:43
comments: true
categories: Mybatis源码解析
tags: 
    - 源码解析
    - Mybatis
    
keywords: Mockito 
description: 在学习源码之前，需要提前做的一些工作。准备好相关环境，这样就可以根据测试用例一步步跟进代码。

---

# 下载源码
到github下载mybatis3就可以了


# 创建数据库和表格
数据库名字为 test_db
表创建语句，及插入数据:

```
CREATE TABLE STUDENTS (
stud_id int(11) NOT NULL AUTO_INCREMENT,
name varchar(50) NOT NULL,
email varchar(50) NOT NULL,
dob date DEFAULT NULL,
PRIMARY KEY (stud_id)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=latin1;

/*Sample Data for the students table */
insert into students(stud_id,name,email,dob)
values (1,'Student1','student1@gmail.com','1983-06-25');
insert into students(stud_id,name,email,dob)
values (2,'Student2','student2@gmail.com','1983-06-25');
```

# 配置
用intellij idea或其他别的ide打开mybatis项目
## pom.xml增加配置
在mybatis的pom.xml配置中增加以下配置:
```
<dependency>
  <groupId>mysql</groupId>
  <artifactId>mysql-connector-java</artifactId>
  <version>5.1.22</version>
  <scope>runtime</scope>
</dependency>
```

## resource配置
在test目录下增加resource文件夹，并设置为test resource。
在文件夹下创建mybatis配置文件 mybatis-config.xml：
```
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE configuration PUBLIC "-//mybatis.org//DTD Config 3.0//EN" "http://mybatis.org/dtd/mybatis-3-config.dtd">
<configuration>
    <typeAliases>
        <typeAlias alias="Student" type="cn.zhengjianglong.sshdemo.entity.Student" />
    </typeAliases>

    <environments default="development">
        <environment id="development">
            <transactionManager type="JDBC" />
            <dataSource type="POOLED">
                <property name="driver" value="com.mysql.jdbc.Driver" />
                <property name="url" value="jdbc:mysql://localhost:3306/test_db" />
                <property name="username" value="root" />
                <property name="password" value="admin" />
            </dataSource>
        </environment>
    </environments>
    <mappers>
        <mapper resource="mapper/StudentMapper.xml" />
    </mappers>
</configuration>
```

在resource文件夹下创建文件夹mapper，并在mapper下新建StudentMapper.xml 
```
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN"
        "http://mybatis.org/dtd/mybatis-3-mapper.dtd">
<mapper namespace="cn.zhengjianglong.sshdemo.entity.mapper.StudentMapper">
    <resultMap type="Student" id="StudentResult">
        <id property="studId" column="stud_id"/>
        <result property="name" column="name"/>
        <result property="email" column="email"/>
        <result property="dob" column="dob"/>
    </resultMap>
    <select id="findAllStudents" resultMap="StudentResult">
        SELECT * FROM STUDENTS
    </select>
    <select id="findStudentById" parameterType="int" resultType="Student">
        SELECT STUD_ID AS STUDID, NAME, EMAIL, DOB
        FROM STUDENTS WHERE STUD_ID=#{Id}
    </select>
    <insert id="insertStudent" parameterType="Student">
        INSERT INTO STUDENTS(STUD_ID,NAME,EMAIL,DOB)
        VALUES(#{studId },#{name},#{email},#{dob})
    </insert>
</mapper>
```


# 创建测试类
## Student
```
package cn.zhengjianglong.sshdemo.entity;

import java.util.Date;

/**
 * @author zhengjianglong
 * @since 2018-02-13
 */
public class Student {
    private Integer studId;
    private String name;
    private String email;
    private Date dob;

   // getter and setter
}

```

## StudentMapper
```
package cn.zhengjianglong.sshdemo.entity.mapper;

import cn.zhengjianglong.sshdemo.entity.Student;

import java.util.List;

/**
 * @author zhengjianglong
 * @since 2018-02-13
 */
public interface StudentMapper {
    /**
     * 获取student对象
     *
     * @param studId
     * @return
     */
    public Student findStudentById(int studId);

    /**
     * 获取列表
     *
     * @return
     */
    List<Student> findAllStudents();

    /**
     * 插入数据
     *
     * @param student
     */
    void insertStudent(Student student);
}
```

## MyBatisSqlSessionFactory
```
public class MyBatisSqlSessionFactory {
    private static SqlSessionFactory sqlSessionFactory;

    public static SqlSessionFactory getSqlSessionFactory() {
        if (sqlSessionFactory == null) {
            InputStream inputStream;
            try {
                inputStream = Resources.
                        getResourceAsStream("mybatis-config.xml");
                sqlSessionFactory = new
                        SqlSessionFactoryBuilder().build(inputStream);
            } catch (IOException e) {
                throw new RuntimeException(e.getCause());
            }
        }
        return sqlSessionFactory;
    }

    public static SqlSession openSession() {
        return getSqlSessionFactory().openSession();
    }
}
```

## StudentService
```
public class StudentService {
    public Student findStudentById(int studId) {
        SqlSession sqlSession = MyBatisSqlSessionFactory.openSession();
        try {
            StudentMapper studentMapper =
                    sqlSession.getMapper(StudentMapper.class);
            return studentMapper.findStudentById(studId);
        } finally {
            sqlSession.close();
        }
    }


    public List<Student> findAllStudents() {
        SqlSession sqlSession =
                MyBatisSqlSessionFactory.openSession();
        try {
            StudentMapper studentMapper =
                    sqlSession.getMapper(StudentMapper.class);
            return studentMapper.findAllStudents();
        } finally {
            sqlSession.close();
        }

    }

    public void insertStudent(Student student) {
        SqlSession sqlSession =
                MyBatisSqlSessionFactory.openSession();
        try {
            StudentMapper studentMapper =
                    sqlSession.getMapper(StudentMapper.class);
            studentMapper.insertStudent(student);
            sqlSession.commit();
        } finally {
            sqlSession.close();
        }
    }
}
```

## StudentServiceTest
```
public class StudentServiceTest {
    private static StudentService studentService;

    @BeforeClass
    public static void setup() {
        studentService = new StudentService();
    }

    @AfterClass
    public static void teardown() {
        studentService = null;
    }

    @Test
    public void testFindAllStudents() {
        List<Student> students = studentService.findAllStudents();
        Assert.assertNotNull(students);
        for (Student student : students) {
            System.out.println(student);
        }
    }

    @Test
    public void testFindStudentById() {
        Student student = studentService.findStudentById(1);
        Assert.assertNotNull(student);
        System.out.println(student);
    }

    @Test
    public void testCreateStudent() {
        Student student = new Student();
        int id = 3;
        student.setStudId(id);
        student.setName("student_" + id);
        student.setEmail("student_" + id + "gmail.com");
    }

}
```

# 参考
 - [1] [ashan博客-mybatis系列](http://blog.csdn.net/ashan_li/article/list)
 - [2] 《Java Persistence with MyBatis 3》





