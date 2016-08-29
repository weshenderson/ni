# Row operations
These are fairly well-optimized operations that operate on rows as units, which
basically means that ni can just scan for newlines and doesn't have to parse
anything else. They include:

- Take first/last N
- Take uniform-random or periodic sample
- Rows matching regex
- Rows satisfying code
- Reorder rows

## First/last
Shorthands for UNIX `head` and `tail`.

```bash
$ ni n:10r3                     # take first 3
1
2
3
$ ni n:10r+3                    # take last 3
8
9
10
$ ni n:10r-7                    # drop first 7
8
9
10
```

## Sampling
```bash
$ ni n:10000rx4000              # take every 4000th row
4000
8000
$ ni n:10000r.0002              # sample uniformly, P(row) = 0.0002
1
6823
8921
9509
```

It's worth noting that uniform sampling, though random, is also deterministic;
by default ni seeds the RNG with 42 every time (though you can change this by
exporting `NI_SEED`). ni also uses an optimized Poisson process to sample rows,
which minimizes calls to `rand()`.

## Regex matching
```bash
$ ni n:10000r/[42]000$/
2000
4000
$ ni n:1000r/[^1]$/r3
2
3
4
```

These regexes are evaluated by Perl, which is likely to be faster than `grep`
for nontrivial patterns.

## Code
`rp` means "select rows for which this Perl expression returns true".

```bash
$ ni n:10000rp'$_ % 100 == 42' r3
42
142
242
```

The expression has access to column accessors and everything else described in
[perl.md](perl.md) (`ni //help/perl`).

Note that whitespace is always required after quoted code.

**TODO:** other languages

## Sorting
ni has four operators that shell out to the UNIX sort command. Two are
alpha-sorts:

```bash
$ ni n:100n:10gr4               # g = 'group'
1
1
10
10
$ ni n:100n:100Gr4              # G = 'group uniq'
1
10
100
11
```

The idea behind `g` as `group` is that this is what you do prior to an
aggregation; i.e. to group related rows together so you can stream into a
reducer (covered in more detail in [facet.md](facet.md) (`ni //help/facet`)).

ni also has two `order` operators that sort numerically:

```bash
$ ni n:100or3                   # o = 'order': sort numeric ascending
1
2
3
$ ni n:100Or3                   # O = 'reverse order'
100
99
98
```

### Specifying sort columns
When used without options, the sort operators sort by a whole row; but you can
append one or more column specifications to change this. I'll generate some
multicolumn data to demonstrate this (see [perl.md](perl.md) (`ni //help/perl`)
for an explanation of the `p` operator).

```bash
$ ni n:100p'r a, sin(a), log(a)' > data         # generate multicolumn data
$ ni data r4
1	0.841470984807897	0
2	0.909297426825682	0.693147180559945
3	0.141120008059867	1.09861228866811
4	-0.756802495307928	1.38629436111989
```

Now we can sort by the second column, which ni refers to as `B` (in general, ni
uses spreadsheet notation: columns are letters, rows are numbers):

```bash
$ ni data oB r4
11	-0.999990206550703	2.39789527279837
55	-0.99975517335862	4.00733318523247
99	-0.999206834186354	4.59511985013459
80	-0.993888653923375	4.38202663467388
```

This is an example of required whitespace between `oB` and `r4`; columns can be
suffixed with `g`, `n`, and/or `r` modifiers to modify how they are sorted
(these behave as described for `sort`'s `-k` option), and ni prefers this
interpretation:

```bash
$ ni data oBr r4                # r suffix = reverse sort
33	0.999911860107267	3.49650756146648
77	0.999520158580731	4.34380542185368
58	0.992872648084537	4.06044301054642
14	0.99060735569487	2.63905732961526
```