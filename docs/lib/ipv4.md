# ipv4 


## `lib.ipv4.ip` 

Build an "ip record" -- `{ a; b; c; d; prefixLength; address; }`, the
shape every other function in this library takes and returns -- from
four octets and a CIDR prefix length.

### Arguments

`a`, `b`, `c`, `d` (`Int`): The four octets

`prefixLength` (`Int`): The CIDR prefix length

### Example

```nix
ip 10 42 0 5 16
=> { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
```

## `lib.ipv4.cidrIndex` 

Offset an ip record by `idx` addresses, keeping the same `prefixLength`.

### Arguments

`ip`: The ip record to offset

`idx` (`Int`): How many addresses to add (or, if negative, subtract)

### Example

```nix
toCIDR (cidrIndex (fromString "10.42.0.0/24") 5)
=> "10.42.0.5/24"
```

## `lib.ipv4.toCIDR` 

Render an ip record as a CIDR string.

### Arguments

`addr`: The ip record to render

### Example

```nix
toCIDR (ip 10 42 0 5 16)
=> "10.42.0.5/16"
```

## `lib.ipv4.toNetworkAddress` 

Drop the individual octets from an ip record, keeping just `address`
and `prefixLength`.

### Arguments

`addr`: The ip record to trim

### Example

```nix
toNetworkAddress (ip 10 42 0 5 16)
=> { address = "10.42.0.5"; prefixLength = 16; }
```

## `lib.ipv4.toNumber` 

Convert an ip record to its 32-bit integer representation.

### Arguments

`addr`: The ip record to convert

### Example

```nix
toNumber (ip 10 42 0 5 16)
=> 170524677
```

## `lib.ipv4.fromNumber` 

Build an ip record from its 32-bit integer representation and a prefix
length. The inverse of `toNumber`.

### Arguments

`addr` (`Int`): The 32-bit address

`prefixLength` (`Int`): The CIDR prefix length

### Example

```nix
fromNumber 170524677 16
=> { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
```

## `lib.ipv4.fromString` 

Parse a CIDR string into an ip record.

### Arguments

`str` (`String`): A string in `"a.b.c.d/prefixLength"` form

### Example

```nix
fromString "10.42.0.5/16"
=> { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
```

## `lib.ipv4.fromIPString` 

Parse a bare dotted-decimal string plus a separate prefix length into
an ip record.

### Arguments

`str` (`String`): A string in `"a.b.c.d"` form, with no prefix length

`prefixLength` (`Int`): The CIDR prefix length

### Example

```nix
fromIPString "10.42.0.5" 16
=> { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
```

## `lib.ipv4.network` 

Zero out the host bits of an ip record, returning the base address of
its subnet.

### Arguments

`addr`: The ip record to normalize

### Example

```nix
toCIDR (network (fromString "10.42.3.7/24"))
=> "10.42.3.0/24"
```


