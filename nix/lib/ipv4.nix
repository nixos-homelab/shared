{ lib, ... }:
rec {
  # https://github.com/LumiGuide/lumi-example/blob/92d614f3f592d30924258328bae4026922b7fd0a/nix/lib.nix#L41-L89
  /**
    Build an "ip record" -- `{ a; b; c; d; prefixLength; address; }`, the
    shape every other function in this library takes and returns -- from
    four octets and a CIDR prefix length.

    # Arguments

    `a`, `b`, `c`, `d` (`Int`): The four octets

    `prefixLength` (`Int`): The CIDR prefix length

    # Example

    ```nix
    ip 10 42 0 5 16
    => { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
    ```
  */
  ip = a: b: c: d: prefixLength: {
    inherit
      a
      b
      c
      d
      prefixLength
      ;
    address = "${toString a}.${toString b}.${toString c}.${toString d}";
  };

  /**
    Offset an ip record by `idx` addresses, keeping the same `prefixLength`.

    # Arguments

    `ip`: The ip record to offset

    `idx` (`Int`): How many addresses to add (or, if negative, subtract)

    # Example

    ```nix
    toCIDR (cidrIndex (fromString "10.42.0.0/24") 5)
    => "10.42.0.5/24"
    ```
  */
  cidrIndex = ip: idx: (fromNumber ((toNumber ip) + idx) ip.prefixLength);

  /**
    Render an ip record as a CIDR string.

    # Arguments

    `addr`: The ip record to render

    # Example

    ```nix
    toCIDR (ip 10 42 0 5 16)
    => "10.42.0.5/16"
    ```
  */
  toCIDR = addr: "${addr.address}/${toString addr.prefixLength}";

  /**
    Drop the individual octets from an ip record, keeping just `address`
    and `prefixLength`.

    # Arguments

    `addr`: The ip record to trim

    # Example

    ```nix
    toNetworkAddress (ip 10 42 0 5 16)
    => { address = "10.42.0.5"; prefixLength = 16; }
    ```
  */
  toNetworkAddress =
    addr: with addr; {
      inherit address prefixLength;
    };

  /**
    Convert an ip record to its 32-bit integer representation.

    # Arguments

    `addr`: The ip record to convert

    # Example

    ```nix
    toNumber (ip 10 42 0 5 16)
    => 170524677
    ```
  */
  toNumber = addr: with addr; a * 16777216 + b * 65536 + c * 256 + d;

  /**
    Build an ip record from its 32-bit integer representation and a prefix
    length. The inverse of `toNumber`.

    # Arguments

    `addr` (`Int`): The 32-bit address

    `prefixLength` (`Int`): The CIDR prefix length

    # Example

    ```nix
    fromNumber 170524677 16
    => { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
    ```
  */
  fromNumber =
    addr: prefixLength:
    let
      aBlock = a * 16777216;
      bBlock = b * 65536;
      cBlock = c * 256;
      a = addr / 16777216;
      b = (addr - aBlock) / 65536;
      c = (addr - aBlock - bBlock) / 256;
      d = addr - aBlock - bBlock - cBlock;
    in
    ip a b c d prefixLength;

  /**
    Parse a CIDR string into an ip record.

    # Arguments

    `str` (`String`): A string in `"a.b.c.d/prefixLength"` form

    # Example

    ```nix
    fromString "10.42.0.5/16"
    => { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
    ```
  */
  fromString =
    with lib;
    str:
    let
      splits1 = splitString "." str;
      splits2 = flatten (map (x: splitString "/" x) splits1);

      e = i: toInt (builtins.elemAt splits2 i);
    in
    ip (e 0) (e 1) (e 2) (e 3) (e 4);

  /**
    Parse a bare dotted-decimal string plus a separate prefix length into
    an ip record.

    # Arguments

    `str` (`String`): A string in `"a.b.c.d"` form, with no prefix length

    `prefixLength` (`Int`): The CIDR prefix length

    # Example

    ```nix
    fromIPString "10.42.0.5" 16
    => { a = 10; b = 42; c = 0; d = 5; prefixLength = 16; address = "10.42.0.5"; }
    ```
  */
  fromIPString = str: prefixLength: fromString "${str}/${toString prefixLength}";

  /**
    Zero out the host bits of an ip record, returning the base address of
    its subnet.

    # Arguments

    `addr`: The ip record to normalize

    # Example

    ```nix
    toCIDR (network (fromString "10.42.3.7/24"))
    => "10.42.3.0/24"
    ```
  */
  network =
    addr:
    let
      pfl = addr.prefixLength;
      pow =
        n: i:
        if i == 1 then
          n
        else if i == 0 then
          1
        else
          n * pow n (i - 1);

      shiftAmount = pow 2 (32 - pfl);
    in
    fromNumber ((toNumber addr) / shiftAmount * shiftAmount) pfl;
}
