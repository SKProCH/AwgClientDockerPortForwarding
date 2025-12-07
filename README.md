# AmneziaWG Docker Client for port forwarding

Docker container that runs [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go) VPN client and lets port forward traffic from your server. 

## What is this for?

When you have a private server that’s not publicly accessible from the Internet (for example, because it’s behind NAT), but you want to expose a service running on it to public Internet traffic, you can do so via WireGuard - as long as you have another server that is publicly accessible from the Internet. 

This docker container helps with that. It doesn't require the amnezia-wg kernel module, so it can be used in lxc containers and other environments where kernel modules are not available.

It allows port forwarding while keeping the original IP address of the client via policy based routing.

## Quick Start

1. **Get your AmneziaWG config** from your VPN provider and save it as `awg.conf`

2. **Create `compose.yaml`:**
    ```yaml
    services:
      amnezia:
        image: ghcr.io/skproch/awg-client:main
        container_name: amnezia-client
        cap_add:
          - NET_ADMIN
        devices:
          - /dev/net/tun:/dev/net/tun
        sysctls:
          - net.ipv4.conf.all.src_valid_mark=1
        volumes:
          - ./awg.conf:/config/awg0.conf:ro
        restart: unless-stopped
    ```

3. Integrate with existing services.  

    There is 2 variants:

    a. Make your services use awg-client network, e.g. traefik:

      ```yaml
      services:
        amnezia:
          image: ghcr.io/skproch/awg-client:main
          container_name: amnezia-client
          cap_add:
            - NET_ADMIN
          devices:
            - /dev/net/tun:/dev/net/tun
          sysctls:
            - net.ipv4.conf.all.src_valid_mark=1
          volumes:
            - ./awg.conf:/config/awg0.conf:ro
          restart: unless-stopped
          # !!! PORTS FROM TRAEFIK HERE !!!
          # Because the network stack is now shared, ports are published by the "owner" of the network.
          ports:
            - "80:80"     # HTTP
            - "443:443"   # HTTPS
            - "8080:8080" # Traefik Dashboard / API
            - "808:808"   # Your custom port

        traefik:
          image: "traefik:v3.5"
          depends_on:
            - amnezia-client # Wait till VPN is up
          
          # !!! MAGIC HERE !!!
          # Traefik uses the network interface of the amnezia-client container.
          # For Traefik, the wg0 interface is now "native".
          network_mode: service:amnezia-client
      ```
    b. Make awg-client use your host network:
    ```yaml
    services:
      amnezia:
        image: ghcr.io/skproch/awg-client:main
        container_name: amnezia-client
        # Enable host network mode. The awg0 interface will appear on the host.
        network_mode: host
        # Grant permissions to manage the host's network stack
        privileged: true
        cap_add:
          - NET_ADMIN
        devices:
          - /dev/net/tun:/dev/net/tun
        sysctls:
          - net.ipv4.conf.all.src_valid_mark=1
        volumes:
          - ./awg.conf:/config/awg0.conf:ro
        restart: unless-stopped
      
      traefik:
        ...
    ```

4. **Start:**
```bash
docker-compose up -d
```

5. **Verify:**
```bash
docker logs amnezia-client
```

6. Enable packet forwarding in your VPN server
```bash
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-sysctl.conf
sysctl --system
```

7. Enable packet forwarding

    You can add this to your wg.conf:
    ```
    PreUp = iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 2000 -j DNAT --to-destination 10.0.0.1:8080
    PostDown = iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 2000 -j DNAT --to-destination 10.0.0.1:8080
    ```

    Replace `2000` with your desired port, and `10.0.0.1` with your client IP address. Look for `Address` in your client config, e.g.: 
    ```
    Address = 10.8.0.2/32
    ```
    Or do it manually.

    > [!TIP]
    > If you are using awg server inside a docker container (like wg-easy) you also need to forward your port to docker container.

    > [!IMPORTANT]  
    > If you are using awg server inside a docker container (like wg-easy) you also need to forward your port to docker container.