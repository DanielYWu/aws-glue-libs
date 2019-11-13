FROM python:3.6.9-stretch

ARG GLUE_VER
ARG SPARK_URL
ARG MAVEN_URL
ARG PYTHON_BIN

RUN apt-get update && apt-get install -y --no-install-recommends \
		bzip2 \
		unzip \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home

# do some fancy footwork to create a JAVA_HOME that's cross-architecture-safe
RUN ln -svT "/usr/lib/jvm/java-8-openjdk-$(dpkg --print-architecture)" /docker-java-home
ENV JAVA_HOME /docker-java-home

ENV JAVA_VERSION 8u212
ENV JAVA_DEBIAN_VERSION 8u212-b01-1~deb9u1

RUN set -ex; \
	\
# deal with slim variants not having man page directories (which causes "update-alternatives" to fail)
	if [ ! -d /usr/share/man/man1 ]; then \
		mkdir -p /usr/share/man/man1; \
	fi; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		openjdk-8-jdk \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
# verify that "docker-java-home" returns what we expect
	[ "$(readlink -f "$JAVA_HOME")" = "$(docker-java-home)" ]; \
	\
# update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
	update-alternatives --get-selections | awk -v home="$(readlink -f "$JAVA_HOME")" 'index($3, home) == 1 { $2 = "manual"; print | "update-alternatives --set-selections" }'; \
# ... and verify that it actually worked for one of the alternatives we care about
	update-alternatives --query java | grep -q 'Status: manual'

# If you're reading this and have any feedback on how this image could be
# improved, please open an issue or a pull request so we can discuss it!
#
#   https://github.com/docker-library/openjdk/issues


RUN apt-get update && apt-get install awscli zip git tar ${PYTHON_BIN} ${PYTHON_BIN}-pip -y && pip3 install pytest

ADD ${MAVEN_URL} /tmp/maven.tar.gz
ADD ${SPARK_URL} /tmp/spark.tar.gz

RUN tar zxvf /tmp/maven.tar.gz -C ~/ && tar zxvf /tmp/spark.tar.gz -C ~/ && rm -rf /tmp/*
RUN echo 'export SPARK_HOME="$(ls -d /root/*spark*)"; export MAVEN_HOME="$(ls -d /root/*maven*)"; export PATH="$PATH:$MAVEN_HOME/bin:$SPARK_HOME/bin:/glue/bin"' >> ~/.bashrc
ENV PYSPARK_PYTHON "${PYTHON_BIN}"

WORKDIR /glue
ADD . /glue

RUN bash -l -c 'bash ~/.profile && bash /glue/bin/glue-setup.sh && sed -i -e "/^mvn/ s/^/#/" /glue/bin/glue-setup.sh; rm $(ls -d /glue/*jars*)/netty* && wget -O /glue/conf/log4j.properties https://gist.githubusercontent.com/svajiraya/aecb45c038e7bba86429646a68b542bb/raw/0cc6229d3b745a0092be75bbbf9476fa17318004/log4j.properties && sed -i -e "/enableHiveSupport()/d" $SPARK_HOME/python/pyspark/shell.py'
CMD [ "bash", "-l", "-c", "gluepyspark" ]
