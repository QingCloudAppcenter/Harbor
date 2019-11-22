#!/usr/bin/env python

import hmac
import hashlib
from struct import Struct
from operator import xor
from itertools import izip, starmap


_pack_int = Struct('>I').pack
def pbkdf2_hex(data, salt, iterations=4096, keylen=16, hashfunc=None):
    return pbkdf2_bin(data, salt, iterations, keylen, hashfunc).encode('hex')
def pbkdf2_bin(data, salt, iterations=4096, keylen=16, hashfunc=None):
    hashfunc = hashfunc or hashlib.sha1
    mac = hmac.new(data, None, hashfunc)
    def _pseudorandom(x, mac=mac):
        h = mac.copy()
        h.update(x)
        return map(ord, h.digest())
    buf = []
    for block in xrange(1, -(-keylen // mac.digest_size) + 1):
        rv = u = _pseudorandom(salt + _pack_int(block))
        for i in xrange(iterations - 1):
            u = _pseudorandom(''.join(map(chr, u)))
            rv = starmap(xor, izip(rv, u))
        buf.extend(rv)
    return ''.join(map(chr, buf))[:keylen]
rv = pbkdf2_hex('Harbor12345', 'x9vtop1qd0cnzfg7cus8h613df1imq8f', 4096, 16)
print(rv)
