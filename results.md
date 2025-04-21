# Ryzen 9 5900X (Zen3)
Observed execution pipe capabilities:
- 3 mem read (2 for vmovdqu)
- 2 mem write

Agner Fog's [microarchitecture.pdf](https://www.agner.org/optimize/microarchitecture.pdf) writes:
> The Zen 3 can do three memory operations per clock cycle, with at most two memory writes, i.e. three reads, or two reads and one write, or one read and two writes.

Only reference for 2 load / cycle with 128 & 256 bit registers i could find is an [AMD Slide](https://images.anandtech.com/doci/16214/Zen3_arch_17.jpg), but it only mentions slowdown for 256b.

## cache-test
![results](docs/cache_ryzen_5900x.png)

## read-unroll
```
Calibrating...
 3693 MHz
Read_x1
 Min: 819589701 (221.92ms), 1024.000MiB @ 4.506GiB/s
 Max: 849021486 (229.89ms), 1024.000MiB @ 4.350GiB/s
 Avg: 824533355 (223.26ms), 1024.000MiB @ 4.479GiB/s
Read_x1 unaligned
 Min: 825003948 (223.39ms), 1024.000MiB @ 4.476GiB/s
 Max: 846906098 (229.32ms), 1024.000MiB @ 4.361GiB/s
 Avg: 828374786 (224.30ms), 1024.000MiB @ 4.458GiB/s
Read_x2
 Min: 412430416 (111.68ms), 1024.000MiB @ 8.955GiB/s
 Max: 424811763 (115.03ms), 1024.000MiB @ 8.694GiB/s
 Avg: 414705760 (112.29ms), 1024.000MiB @ 8.905GiB/s
Read_x3
 Min: 275976710 (74.73ms), 1024.000MiB @ 13.382GiB/s
 Max: 295710956 (80.07ms), 1024.000MiB @ 12.489GiB/s
 Avg: 278222241 (75.34ms), 1024.000MiB @ 13.274GiB/s
Read_x3 unaligned
 Min: 554807267 (150.23ms), 1024.000MiB @ 6.657GiB/s
 Max: 563375122 (152.55ms), 1024.000MiB @ 6.555GiB/s
 Avg: 555570093 (150.43ms), 1024.000MiB @ 6.647GiB/s
Read_x4
 Min: 276606709 (74.90ms), 1024.000MiB @ 13.352GiB/s
 Max: 304651377 (82.49ms), 1024.000MiB @ 12.122GiB/s
 Avg: 277954456 (75.26ms), 1024.000MiB @ 13.287GiB/s
Read_x5
 Min: 276804955 (74.95ms), 1024.000MiB @ 13.342GiB/s
 Max: 307507148 (83.26ms), 1024.000MiB @ 12.010GiB/s
 Avg: 279118834 (75.58ms), 1024.000MiB @ 13.231GiB/s
```

## write-unroll
```
Calibrating...
 3693 MHz
Write_x1
 Min: 827516507 (224.07ms), 1024.000MB @ 4.463GB/s, 0 page faults
 Max: 1097065059 (297.05ms), 1024.000MB @ 3.366GB/s, 0 page faults
 Avg: 847630286 (229.51ms), 1024.000MB @ 4.357GB/s, 0 page faults
Write_x2
 Min: 417983339 (113.18ms), 1024.000MB @ 8.836GB/s, 0 page faults
 Max: 446370812 (120.86ms), 1024.000MB @ 8.274GB/s, 0 page faults
 Avg: 424060731 (114.82ms), 1024.000MB @ 8.709GB/s, 0 page faults
Write_x3
 Min: 419044277 (113.47ms), 1024.000MB @ 8.813GB/s, 0 page faults
 Max: 441158289 (119.45ms), 1024.000MB @ 8.371GB/s, 0 page faults
 Avg: 422910913 (114.51ms), 1024.000MB @ 8.733GB/s, 0 page faults
Write_x4
 Min: 417710094 (113.10ms), 1024.000MB @ 8.841GB/s, 0 page faults
 Max: 488640055 (132.31ms), 1024.000MB @ 7.558GB/s, 0 page faults
 Avg: 422825597 (114.49ms), 1024.000MB @ 8.734GB/s, 0 page faults
Write_x5
 Min: 416269536 (112.71ms), 1024.000MB @ 8.872GB/s, 0 page faults
 Max: 442405411 (119.79ms), 1024.000MB @ 8.348GB/s, 0 page faults
 Avg: 422462900 (114.39ms), 1024.000MB @ 8.742GB/s, 0 page faults
```

## read-width
```
Calibrating...
 3693 MHz
Read_4x3
 Min: 69669705 (18.86ms), 1024.000MB @ 53.009GB/s, 0 page faults
 Max: 100911224 (27.32ms), 1024.000MB @ 36.598GB/s, 0 page faults
 Avg: 71537192 (19.37ms), 1024.000MB @ 51.626GB/s, 0 page faults
Read_8x3
 Min: 34733454 (9.40ms), 1024.000MB @ 106.328GB/s, 0 page faults
 Max: 54565639 (14.77ms), 1024.000MB @ 67.683GB/s, 0 page faults
 Avg: 35633646 (9.65ms), 1024.000MB @ 103.642GB/s, 0 page faults
Read_16x2
 Min: 25624905 (6.94ms), 1024.000MB @ 144.124GB/s, 0 page faults
 Max: 45205638 (12.24ms), 1024.000MB @ 81.697GB/s, 0 page faults
 Avg: 26200042 (7.09ms), 1024.000MB @ 140.960GB/s, 0 page faults
Read_16x3
 Min: 25942772 (7.02ms), 1024.000MB @ 142.358GB/s, 0 page faults
 Max: 45252776 (12.25ms), 1024.000MB @ 81.612GB/s, 0 page faults
 Avg: 26337957 (7.13ms), 1024.000MB @ 140.222GB/s, 0 page faults
Read_32x2
 Min: 12758525 (3.45ms), 1024.000MB @ 289.465GB/s, 0 page faults
 Max: 31929557 (8.65ms), 1024.000MB @ 115.666GB/s, 0 page faults
 Avg: 13129232 (3.56ms), 1024.000MB @ 281.292GB/s, 0 page faults
Read_32x3
 Min: 12796783 (3.47ms), 1024.000MB @ 288.600GB/s, 0 page faults
 Max: 32733197 (8.86ms), 1024.000MB @ 112.826GB/s, 0 page faults
 Avg: 13416611 (3.63ms), 1024.000MB @ 275.267GB/s, 0 page faults
```

## cache-test
```
Calibrating...
 3693 MHz
Read from 32KB buffer
 Min: 13164896 (3.56ms), 1024.000MB @ 280.527GB/s, 0 page faults
 Max: 14776319 (4.00ms), 1024.000MB @ 249.935GB/s, 0 page faults
 Avg: 13363121 (3.62ms), 1024.000MB @ 276.366GB/s, 0 page faults
Read from 64KB buffer
 Min: 26237810 (7.10ms), 1024.000MB @ 140.755GB/s, 0 page faults
 Max: 27174687 (7.36ms), 1024.000MB @ 135.903GB/s, 0 page faults
 Avg: 26443649 (7.16ms), 1024.000MB @ 139.660GB/s, 0 page faults
Read from 256KB buffer
 Min: 26106164 (7.07ms), 1024.000MB @ 141.465GB/s, 0 page faults
 Max: 28239071 (7.65ms), 1024.000MB @ 130.780GB/s, 0 page faults
 Avg: 26455500 (7.16ms), 1024.000MB @ 139.597GB/s, 0 page faults
Read from 512KB buffer
 Min: 27908730 (7.56ms), 1024.000MB @ 132.328GB/s, 0 page faults
 Max: 36267067 (9.82ms), 1024.000MB @ 101.831GB/s, 0 page faults
 Avg: 28523643 (7.72ms), 1024.000MB @ 129.476GB/s, 0 page faults
Read from 1024KB buffer
 Min: 31575763 (8.55ms), 1024.000MB @ 116.960GB/s, 0 page faults
 Max: 36719429 (9.94ms), 1024.000MB @ 100.577GB/s, 0 page faults
 Avg: 32411506 (8.78ms), 1024.000MB @ 113.945GB/s, 0 page faults
Read from 16384KB buffer
 Min: 31912981 (8.64ms), 1024.000MB @ 115.725GB/s, 0 page faults
 Max: 45114063 (12.22ms), 1024.000MB @ 81.862GB/s, 0 page faults
 Avg: 32829990 (8.89ms), 1024.000MB @ 112.492GB/s, 0 page faults
Read from 32768KB buffer
 Min: 73865690 (20.00ms), 1024.000MB @ 49.998GB/s, 0 page faults
 Max: 118180997 (32.00ms), 1024.000MB @ 31.250GB/s, 0 page faults
 Avg: 82821814 (22.43ms), 1024.000MB @ 44.591GB/s, 0 page faults
Read from 65536KB buffer
 Min: 108855517 (29.48ms), 1024.000MB @ 33.927GB/s, 0 page faults
 Max: 149652309 (40.52ms), 1024.000MB @ 24.678GB/s, 0 page faults
 Avg: 115372042 (31.24ms), 1024.000MB @ 32.010GB/s, 0 page faults
Read from 131072KB buffer
 Min: 132210213 (35.80ms), 1024.000MB @ 27.934GB/s, 0 page faults
 Max: 170775128 (46.24ms), 1024.000MB @ 21.626GB/s, 0 page faults
 Avg: 139851031 (37.87ms), 1024.000MB @ 26.407GB/s, 0 page faults
Read from 1048576KB buffer
 Min: 144117886 (39.02ms), 1024.000MB @ 25.626GB/s, 0 page faults
 Max: 167882764 (45.46ms), 1024.000MB @ 21.998GB/s, 0 page faults
 Avg: 146158358 (39.58ms), 1024.000MB @ 25.268GB/s, 0 page faults
```