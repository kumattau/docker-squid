# ============================================================================
FROM rockylinux:8 AS squid
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

ARG URL="http://www.squid-cache.org/Versions/v6/squid-6.6.tar.gz"

RUN dnf -y update
RUN dnf -y install dnf-plugins-core
RUN dnf -y groups install development
RUN dnf -y install kernel-devel kernel-headers
RUN dnf -y builddep squid --enablerepo=powertools

WORKDIR /usr/local/src
RUN curl -L -o "${URL##*/}" "$URL"
RUN tar zxf "${URL##*/}" --transform 's|^[^/]+|squid|x'

WORKDIR /usr/local/src/squid
# --disable-security-cert-validators for missing perl-Crypt-OpenSSL-X509 on distro repo
# --without-systemd and --without-xml2 for reducing installed packages
RUN ./configure \
    --prefix=/usr/local/squid \
    --disable-arch-native \
    --enable-delay-pools \
    --enable-ecap \
    --enable-cachemgr-hostname=localhost \
    --enable-cache-digests \
    --enable-linux-netfilter \
    --enable-ssl-crtd \
    --disable-security-cert-validators \
    --enable-x-accelerator-vary \
    --with-openssl \
    --without-systemd \
    --without-xml2 \
    && :
RUN make -j "$(nproc)" && make check
RUN make install-strip

WORKDIR /usr/local/squid
RUN dnf -y install squid
RUN { \
    find ./ -type f | /usr/lib/rpm/find-requires && \
    rpm -qv --requires squid | awk '$1 ~ /^(auto|manual):/ && $2 !~ /^lib(xml2|systemd)\.so/{$1=""; print substr($0,2)}'; \
    } | sort -u > ./share/req.txt
RUN readarray -t reqs < ./share/req.txt && \
    dnf -y install "${reqs[@]}"
RUN ./libexec/security_file_certgen -c -s var/cache/squid/ssl_db -M 4MB
RUN mkdir -p var/lib/squid && \
    { yes "" || :; } | openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -keyout var/lib/squid/ssl-bump.key -out var/lib/squid/ssl-bump.crt && \
    cat var/lib/squid/ssl-bump.key var/lib/squid/ssl-bump.crt > var/lib/squid/ssl-bump.pem

RUN dnf -y install epel-release
RUN dnf -y install upx
RUN shopt -s dotglob && shopt -s nullglob && shopt -s globstar && \
    { upx --best --lzma {bin,sbin,libexec}/**/* || :; }

RUN rm -fr share/man/
RUN chown -R nobody:nobody var/

# ============================================================================
FROM rockylinux:8 AS chroot
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

COPY <<'EOT' /chroot/etc/dnf/dnf.conf
[main]
tsflags=nodocs
install_weak_deps=false
EOT

COPY --from=squid /usr/local/squid/share/req.txt /tmp/req.txt

RUN dnf -y --installroot=/chroot/ --releasever=/ install basesystem glibc-minimal-langpack

RUN readarray -t reqs < /tmp/req.txt && \
    dnf -y --installroot=/chroot/ install "${reqs[@]}"
RUN dnf -y --installroot=/chroot/ install ca-certificates crypto-policies openssl

RUN dnf -y --installroot=/chroot/ install crypto-policies-scripts
RUN chroot /chroot/ update-crypto-policies --set LEGACY --no-reload
RUN dnf -y --installroot=/chroot/ remove crypto-policies-scripts

RUN rpm --root=/chroot/ -qa | sort -u > /chroot/usr/share/rpm.txt

COPY --from=busybox:musl /bin/busybox /chroot/usr/local/bin/
RUN chroot /chroot/ /usr/local/bin/busybox --install -s /usr/local/bin/
RUN for x in /chroot/usr/local/bin/*; do rm -fv "${x/local\//}" && ln -s "${x/chroot\//}" "${x/local\//}"; done

RUN dnf -y install epel-release
RUN dnf -y install upx
RUN shopt -s dotglob && shopt -s nullglob && shopt -s globstar && \
    { upx --best --lzma /chroot/usr/{,local/}{bin,sbin,libexec}/**/* || :; }

RUN dnf -y install xz
RUN cd /chroot/usr/share && XZ_OPT=-9 tar Jcf licenses.tar.xz licenses && rm -fr licenses/

RUN shopt -s dotglob && shopt -s nullglob && shopt -s globstar && \
    rm -fr /chroot/{var/lib/{rpm,yum,dnf}/,{dev,proc,sys,tmp}/*,**/{tmp,cache,log}/*} 

# ============================================================================
FROM scratch
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

COPY --from=chroot /chroot/          /
COPY --from=squid  /usr/local/squid/ /usr/local/squid/

USER nobody
WORKDIR /usr/local/squid
CMD ["/bin/bash", "-c", "rm -f var/run/squid.pid && exec ./sbin/squid -N"]

# ============================================================================
