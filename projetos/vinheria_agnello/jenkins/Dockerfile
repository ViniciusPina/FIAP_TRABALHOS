# syntax=docker/dockerfile:1
# Jenkins da Vinheria Agnello: Jenkins LTS + plugins + Configuration as Code,
# com Docker CLI/Compose (Docker-out-of-Docker), Trivy e Gitleaks embarcados.
FROM docker:28-cli AS docker-cli
FROM aquasec/trivy:0.58.1 AS trivy
FROM zricethezav/gitleaks:v8.21.2 AS gitleaks

FROM jenkins/jenkins:lts-jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends jq \
 && rm -rf /var/lib/apt/lists/*
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=gitleaks /usr/bin/gitleaks /usr/local/bin/gitleaks
RUN mkdir -p /var/publicacao && chown jenkins:jenkins /var/publicacao

USER jenkins
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/casc.yaml
