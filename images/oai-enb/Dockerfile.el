ARG REGISTRY=localhost
FROM $REGISTRY/oai-build-base:latest.el AS builder

ARG GIT_TAG=v1.2.2

WORKDIR /root

RUN if [ "$EURECOM_PROXY" == true ]; then git config --global http.proxy http://:@proxy.eurecom.fr:8080; fi

RUN git clone --depth=1 --branch=$GIT_TAG https://gitlab.eurecom.fr/oai/openairinterface5g.git
COPY patches patches/
RUN patch -p1 -d openairinterface5g < patches/disable_building_nasmesh_and_rbtool.patch \
    && patch -p1 -d openairinterface5g < patches/disable_sched_fifo_fail_exits.patch
RUN cd openairinterface5g/cmake_targets \
    && ln -sf /usr/local/bin/asn1c_oai /usr/local/bin/asn1c \
    && ln -sf /usr/local/share/asn1c_oai /usr/local/share/asn1c \
    && ./build_oai -c --eNB -w USRP --verbose-compile


FROM registry.redhat.io/ubi8/ubi
LABEL name="oai-enb" \
      version="$GIT_TAG" \
      maintainer="Frank A. Zdarsky <fzdarsky@redhat.com>" \
      io.k8s.description="openairinterface5g eNB $GIT_TAG." \
      io.openshift.tags="oai,enb" \
      io.openshift.non-scalable="true"

RUN REPOLIST="codeready-builder-for-rhel-8-x86_64-rpms" \
    PKGLIST="boost libconfig lksctp-tools protobuf-c iproute iputils procps-ng bind-utils" \
    # && yum -y upgrade-minimal --setopt=tsflags=nodocs --security --sec-severity=Critical --sec-severity=Important && \
    && yum -y install --enablerepo ${REPOLIST} --setopt=tsflag=nodocs ${PKGLIST} \
    && yum -y install http://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/x/xforms-1.2.4-5.el7.x86_64.rpm \
    && yum -y clean all \
    && rm -rf /var/cache/yum

ENV APP_ROOT=/opt/oai-enb
ENV PATH=${APP_ROOT}:${PATH} HOME=${APP_ROOT}
COPY --from=builder /root/openairinterface5g/cmake_targets/lte_build_oai/build/lte-softmodem ${APP_ROOT}/bin/
COPY --from=builder /root/openairinterface5g/cmake_targets/lte_build_oai/build/*.so* /lib64/
COPY --from=builder /usr/local/lib64 /lib64
COPY --from=builder /usr/local/bin/uhd_* /usr/local/bin/
COPY --from=builder /usr/local/share/uhd /usr/local/share/uhd
RUN cd /lib64 \
    && ln -sf liboai_eth_transpro.so liboai_transpro.so \
    && ln -sf liboai_usrpdevif.so liboai_device.so \
    && ln -sf libuhd.so.3.15 libuhd.so.3 \
    && ln -sf libuhd.so.3 libuhd.so
COPY scripts ${APP_ROOT}/bin/
COPY configs ${APP_ROOT}/etc/
RUN chmod -R u+x ${APP_ROOT} && \
    chgrp -R 0 ${APP_ROOT} && \
    chmod -R g=u ${APP_ROOT} /etc/passwd
USER 10001
WORKDIR ${APP_ROOT}

# S1U, GTP/UDP
EXPOSE 2152/udp
# ?
EXPOSE 22100/tcp
# S1C, SCTP/UDP
EXPOSE 36412/udp
# X2C, SCTP/UDP
EXPOSE 36422/udp
# IF5 / ORI (control)
EXPOSE 50000/udp
# IF5 / ECPRI (data)
EXPOSE 50001/udp

CMD ["/opt/oai-enb/bin/lte-softmodem", "-O", "/opt/oai-enb/etc/enb.conf"]
ENTRYPOINT ["/opt/oai-enb/bin/entrypoint.sh"]