# syntax = docker/dockerfile:1.3
FROM --platform=linux/amd64 oraclelinux:7-slim


RUN yum install wget -y

ENV CONDA_HOME=/opt/miniconda3
COPY . /opt/program/mlflow
WORKDIR /opt/program/mlflow


RUN sh entrypoint.sh

ENV PATH=$CONDA_HOME/bin:$PATH
RUN echo $PATH

ENV MLFLOW_PORT 5000

RUN pip install -r requirements.txt

EXPOSE ${MLFLOW_PORT}

CMD ["sh", "-c", "mlflow server --host 0.0.0.0 --port $MLFLOW_PORT --artifacts-destination $MLFLOW_ARTIFACT_URI"]
