# Kurento / Coturn Cloud Formation

## Elastic IP

Create an EIP and note the AllocationId:

```
eipalloc-0e2b1e165b43b59e6
```

Update the yaml file with this AllocationId.

## Coturn

Update this line to match the domain in use:

```
certbot certonly --standalone --domains "turn2.xaltexperiences.com"
```

## Cloud Formation

Create stack using yaml file.

## Test

https://icetest.info/

```
stun:turn.xaltexperiences.com:3478
turn:turn.xaltexperiences.com:3478 Username: kurento Credential: kurento
```
