-- Ed25519/SHA-512, adapted from public-domain TweetNaCl (20140427).
-- https://tweetnacl.cr.yp.to/  See README.md for provenance and limitations.
-- Lua 5.1 doubles: field limbs are 16 bits; SHA words are pairs of 32-bit limbs.
local QT = _G.QuestTogether
local E = {}
QT.Ed25519 = E
local floor, MOD = math.floor, 4294967296
local native = bit32 or bit
local function xor(a, b)
	if native then return native.bxor(a, b) % MOD end
	local n, p = 0, 1
	for _ = 1, 32 do
		local x, y = a % 2, b % 2
		if x ~= y then n = n + p end
		a, b, p = floor(a / 2), floor(b / 2), p * 2
	end
	return n
end
local function band(a, b)
	if native then return native.band(a, b) % MOD end
	return (a + b - xor(a, b)) / 2
end
local function word(s, i)
	local a,b,c,d = s:byte(i, i+3)
	return ((a*256+b)*256+c)*256+d
end
local function bytes32(x)
	return string.char(floor(x/16777216)%256, floor(x/65536)%256, floor(x/256)%256, x%256)
end
local function add64(a,b)
	local low = a[2]+b[2]
	return {(a[1]+b[1]+floor(low/MOD))%MOD, low%MOD}
end
local function xor64(a,b) return {xor(a[1],b[1]), xor(a[2],b[2])} end
local function rotate(a,n)
	local h,l = a[1],a[2]
	if n >= 32 then h,l,n = l,h,n-32 end
	if n == 0 then return {h,l} end
	local p,q = 2^n, 2^(32-n)
	return {floor(h/p)+(l%p)*q, floor(l/p)+(h%p)*q}
end
local function shr(a,n) return {floor(a[1]/2^n),floor(a[2]/2^n)+(a[1]%2^n)*2^(32-n)} end
local function sigma(a,x,y,z,small)
	return xor64(xor64(rotate(a,x),rotate(a,y)), small and shr(a,z) or rotate(a,z))
end
-- SHA-512 round constants from public-domain TweetNaCl.
local K = {
{0x428a2f98,0xd728ae22},
{0x71374491,0x23ef65cd},
{0xb5c0fbcf,0xec4d3b2f},
{0xe9b5dba5,0x8189dbbc},
{0x3956c25b,0xf348b538},
{0x59f111f1,0xb605d019},
{0x923f82a4,0xaf194f9b},
{0xab1c5ed5,0xda6d8118},
{0xd807aa98,0xa3030242},
{0x12835b01,0x45706fbe},
{0x243185be,0x4ee4b28c},
{0x550c7dc3,0xd5ffb4e2},
{0x72be5d74,0xf27b896f},
{0x80deb1fe,0x3b1696b1},
{0x9bdc06a7,0x25c71235},
{0xc19bf174,0xcf692694},
{0xe49b69c1,0x9ef14ad2},
{0xefbe4786,0x384f25e3},
{0x0fc19dc6,0x8b8cd5b5},
{0x240ca1cc,0x77ac9c65},
{0x2de92c6f,0x592b0275},
{0x4a7484aa,0x6ea6e483},
{0x5cb0a9dc,0xbd41fbd4},
{0x76f988da,0x831153b5},
{0x983e5152,0xee66dfab},
{0xa831c66d,0x2db43210},
{0xb00327c8,0x98fb213f},
{0xbf597fc7,0xbeef0ee4},
{0xc6e00bf3,0x3da88fc2},
{0xd5a79147,0x930aa725},
{0x06ca6351,0xe003826f},
{0x14292967,0x0a0e6e70},
{0x27b70a85,0x46d22ffc},
{0x2e1b2138,0x5c26c926},
{0x4d2c6dfc,0x5ac42aed},
{0x53380d13,0x9d95b3df},
{0x650a7354,0x8baf63de},
{0x766a0abb,0x3c77b2a8},
{0x81c2c92e,0x47edaee6},
{0x92722c85,0x1482353b},
{0xa2bfe8a1,0x4cf10364},
{0xa81a664b,0xbc423001},
{0xc24b8b70,0xd0f89791},
{0xc76c51a3,0x0654be30},
{0xd192e819,0xd6ef5218},
{0xd6990624,0x5565a910},
{0xf40e3585,0x5771202a},
{0x106aa070,0x32bbd1b8},
{0x19a4c116,0xb8d2d0c8},
{0x1e376c08,0x5141ab53},
{0x2748774c,0xdf8eeb99},
{0x34b0bcb5,0xe19b48a8},
{0x391c0cb3,0xc5c95a63},
{0x4ed8aa4a,0xe3418acb},
{0x5b9cca4f,0x7763e373},
{0x682e6ff3,0xd6b2b8a3},
{0x748f82ee,0x5defb2fc},
{0x78a5636f,0x43172f60},
{0x84c87814,0xa1f0ab72},
{0x8cc70208,0x1a6439ec},
{0x90befffa,0x23631e28},
{0xa4506ceb,0xde82bde9},
{0xbef9a3f7,0xb2c67915},
{0xc67178f2,0xe372532b},
{0xca273ece,0xea26619c},
{0xd186b8c7,0x21c0c207},
{0xeada7dd6,0xcde0eb1e},
{0xf57d4f7f,0xee6ed178},
{0x06f067aa,0x72176fba},
{0x0a637dc5,0xa2c898a6},
{0x113f9804,0xbef90dae},
{0x1b710b35,0x131c471b},
{0x28db77f5,0x23047d84},
{0x32caab7b,0x40c72493},
{0x3c9ebe0a,0x15c9bebc},
{0x431d67c4,0x9c100d4c},
{0x4cc5d4be,0xcb3e42b6},
{0x597f299c,0xfc657e2a},
{0x5fcb6fab,0x3ad6faec},
{0x6c44198c,0x4a475817},
}

function E.Hash(message)
	local length = #message
	local tail = bytes32(floor(length*8/MOD)) .. bytes32(length*8%MOD)
	message = message .. string.char(128) .. string.rep(string.char(0),(111-length)%128+8) .. tail
	local H = {{0x6a09e667,0xf3bcc908},{0xbb67ae85,0x84caa73b},{0x3c6ef372,0xfe94f82b},{0xa54ff53a,0x5f1d36f1},
		{0x510e527f,0xade682d1},{0x9b05688c,0x2b3e6c1f},{0x1f83d9ab,0xfb41bd6b},{0x5be0cd19,0x137e2179}}
	for offset=1,#message,128 do
		local w={}
		for i=1,16 do local p=offset+(i-1)*8; w[i]={word(message,p),word(message,p+4)} end
		for i=17,80 do w[i]=add64(add64(add64(w[i-16],sigma(w[i-15],1,8,7,true)),w[i-7]),sigma(w[i-2],19,61,6,true)) end
		local a,b,c,d,e,f,g,h=H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
		for i=1,80 do
			local ch={xor(band(e[1],f[1]),band(MOD-1-e[1],g[1])),xor(band(e[2],f[2]),band(MOD-1-e[2],g[2]))}
			local maj={xor(xor(band(a[1],b[1]),band(a[1],c[1])),band(b[1],c[1])),xor(xor(band(a[2],b[2]),band(a[2],c[2])),band(b[2],c[2]))}
			local t1=add64(add64(add64(add64(h,sigma(e,14,18,41)),ch),K[i]),w[i])
			local t2=add64(sigma(a,28,34,39),maj)
			h,g,f,e,d,c,b,a=g,f,e,add64(d,t1),c,b,a,add64(t1,t2)
		end
		local values={a,b,c,d,e,f,g,h}
		for i=1,8 do H[i]=add64(H[i],values[i]) end
	end
	local result={}
	for i=1,8 do result[i]=bytes32(H[i][1])..bytes32(H[i][2]) end
	return table.concat(result)
end

local function gf(values)
	local a={}; for i=1,16 do a[i]=values and values[i] or 0 end; return a
end
local zero,one=gf(),gf({1})
local D=gf({0x78a3,0x1359,0x4dca,0x75eb,0xd8ab,0x4141,0x0a4d,0x0070,0xe898,0x7779,0x4079,0x8cc7,0xfe73,0x2b6f,0x6cee,0x5203})
local D2=gf({0xf159,0x26b2,0x9b94,0xebd6,0xb156,0x8283,0x149a,0x00e0,0xd130,0xeef3,0x80f2,0x198e,0xfce7,0x56df,0xd9dc,0x2406})
local X=gf({0xd51a,0x8f25,0x2d60,0xc956,0xa7b2,0x9525,0xc760,0x692c,0xdc5c,0xfdd6,0xe231,0xc0a4,0x53fe,0xcd6e,0x36d3,0x2169})
local Y=gf({0x6658,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666})
local I=gf({0xa0b0,0x4a0e,0x1b27,0xc4ee,0xe478,0xad2f,0x1806,0x2f43,0xd7a7,0x3dfb,0x0099,0x2b4d,0xdf0b,0x4fc1,0x2480,0x2b83})
local function car(o)
	for i=1,16 do
		o[i]=o[i]+65536
		local c=floor(o[i]/65536)
		local nexti=i<16 and i+1 or 1
		o[nexti]=o[nexti]+(c-1)*(i<16 and 1 or 38)
		o[i]=o[i]-c*65536
	end
end
local function sel(p,q,b)
	for i=1,16 do local t=b*(p[i]-q[i]); p[i],q[i]=p[i]-t,q[i]+t end
end
local function pack25519(n)
	local m,t=gf(),gf(n); car(t); car(t); car(t)
	for _=1,2 do
		m[1]=t[1]-0xffed
		for i=2,15 do m[i]=t[i]-0xffff-floor(m[i-1]/65536)%2; m[i-1]=m[i-1]%65536 end
		m[16]=t[16]-0x7fff-floor(m[15]/65536)%2
		local b=floor(m[16]/65536)%2; m[15]=m[15]%65536; sel(t,m,1-b)
	end
	local out={}; for i=1,16 do out[i]=string.char(t[i]%256,floor(t[i]/256)) end
	return table.concat(out)
end
local function unpack25519(s)
	local o=gf(); for i=1,16 do o[i]=s:byte(2*i-1)+s:byte(2*i)*256 end
	o[16]=o[16]%32768; return o
end
local function A(a,b) local o={}; for i=1,16 do o[i]=a[i]+b[i] end; return o end
local function Z(a,b) local o={}; for i=1,16 do o[i]=a[i]-b[i] end; return o end
local function M(a,b)
	local t={}; for i=1,31 do t[i]=0 end
	for i=1,16 do for j=1,16 do t[i+j-1]=t[i+j-1]+a[i]*b[j] end end
	for i=1,15 do t[i]=t[i]+38*t[i+16] end
	local o=gf(t); car(o); car(o); return o
end
local function S(a) return M(a,a) end
local function power(a,first,skip1,skip2)
	local c=gf(a)
	for i=first,0,-1 do c=S(c); if i~=skip1 and i~=skip2 then c=M(c,a) end end
	return c
end
local function parity(a) return pack25519(a):byte(1)%2 end
local function neq(a,b) return pack25519(a)~=pack25519(b) end
local function add(p,q)
	local a=M(Z(p[2],p[1]),Z(q[2],q[1]))
	local b=M(A(p[1],p[2]),A(q[1],q[2]))
	local c=M(M(p[4],q[4]),D2)
	local d=M(p[3],q[3]); d=A(d,d)
	local e,f,g,h=Z(b,a),Z(d,c),A(d,c),A(b,a)
	p[1],p[2],p[3],p[4]=M(e,f),M(h,g),M(g,f),M(e,h)
end
local function pack(p)
	local zi=power(p[3],253,2,4)
	local x,y=M(p[1],zi),M(p[2],zi)
	local r=pack25519(y)
	return r:sub(1,31)..string.char(r:byte(32)+parity(x)*128)
end
local function scalar(q,s)
	local p={gf(),gf(one),gf(one),gf()}
	for i=255,0,-1 do
		local b=floor((s[floor(i/8)+1] or 0)/2^(i%8))%2
		for j=1,4 do sel(p[j],q[j],b) end
		add(q,p); add(p,p)
		for j=1,4 do sel(p[j],q[j],b) end
	end
	return p
end
local function base(s) return scalar({gf(X),gf(Y),gf(one),M(X,Y)},s) end
local order={0xed,0xd3,0xf5,0x5c,0x1a,0x63,0x12,0x58,0xd6,0x9c,0xf7,0xa2,0xde,0xf9,0xde,0x14,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,16}
local function modL(x)
	for i=64,33,-1 do
		local carry=0
		for j=i-32,i-13 do
			x[j]=x[j]+carry-16*x[i]*order[j-(i-32)+1]
			carry=floor((x[j]+128)/256); x[j]=x[j]-carry*256
		end
		x[i-12]=x[i-12]+carry; x[i]=0
	end
	local carry,high=0,floor(x[32]/16)
	for j=1,32 do x[j]=x[j]+carry-high*order[j]; carry=floor(x[j]/256); x[j]=x[j]%256 end
	for j=1,32 do x[j]=x[j]-carry*order[j] end
	local r={}
	for i=1,32 do x[i+1]=x[i+1]+floor(x[i]/256); r[i]=x[i]%256 end
	return r
end
local function bytearray(s) local a={}; for i=1,#s do a[i]=s:byte(i) end; return a end
local function bytes(a,n) local s={}; for i=1,n or #a do s[i]=string.char(a[i]) end; return table.concat(s) end
local function reduce(s) return modL(bytearray(s)) end
local function unpackneg(s)
	local r={gf(),unpack25519(s),gf(one),gf()}
	local num=S(r[2]); local den=M(num,D); num=Z(num,one); den=A(one,den)
	local den2=S(den); local den4=S(den2); local den6=M(den4,den2)
	local t=M(M(den6,num),den); t=power(t,250,1)
	t=M(M(M(t,num),den),den); r[1]=M(t,den)
	if neq(M(S(r[1]),den),num) then r[1]=M(r[1],I) end
	if neq(M(S(r[1]),den),num) then return nil end
	if parity(r[1])==floor(s:byte(32)/128) then r[1]=Z(zero,r[1]) end
	r[4]=M(r[1],r[2]); return r
end
local function secret(seed)
	local d=bytearray(E.Hash(seed)); d[1]=d[1]-d[1]%8; d[32]=d[32]%64+64; return d
end
function E.PublicKey(seed)
	assert(type(seed)=="string" and #seed==32)
	return pack(base(secret(seed)))
end
function E.Sign(seed,message)
	assert(type(seed)=="string" and #seed==32 and type(message)=="string")
	local d=secret(seed); local public=pack(base(d))
	local r=reduce(E.Hash(bytes(d):sub(33,64)..message)); local R=pack(base(r))
	local h=reduce(E.Hash(R..public..message)); local x={}
	for i=1,64 do x[i]=i<=32 and r[i] or 0 end
	for i=1,32 do for j=1,32 do x[i+j-1]=x[i+j-1]+h[i]*d[j] end end
	return R..bytes(modL(x),32)
end
function E.Verify(public,message,signature)
	if type(public)~="string" or #public~=32 or type(message)~="string" or type(signature)~="string" or #signature~=64 then return false end
	-- Reject noncanonical S; do not accept equivalent signatures S + k*L.
	local s=bytearray(signature:sub(33)); local less=false
	for i=32,1,-1 do if s[i]~=order[i] then less=s[i]<order[i]; break end end
	if not less then return false end
	local q=unpackneg(public); if not q then return false end
	local y=pack25519(q[2]); local canonical=public:sub(1,31)..string.char(public:byte(32)%128)
	if y~=canonical then return false end
	local h=reduce(E.Hash(signature:sub(1,32)..public..message))
	local p=scalar(q,h); add(p,base(s))
	return pack(p)==signature:sub(1,32)
end
