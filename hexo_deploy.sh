hexo clean
hexo g

for file in source/_posts/*
do 
    if test -d $file
    then
       path="${file}/images"
       if [ -d ${path} ]
       then
           echo ${path}
           cp -rf ${path}/* public/images/
       fi
    fi
done

