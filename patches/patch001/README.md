## Bug Info
### Files
13.docker-compose.yml.tmpl, line 1
```shell
tmpstr=$(resolvectl | grep -o '[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+' | awk '!x[$0]++' | sed 's/^/      - /')
```
`uniq` cannot remove the same lines when they are not adjacent. For example:
```shell
# when the input like this
aaa
aaa
bbb
ccc
# result after apply uniq
aaa
bbb
ccc
# when the input like this
aaa
bbb
aaa
ccc
# result after apply uniq
aaa
bbb
aaa
ccc
```
### Correction
```shell
# same as uniq, but support same lines which are not adjacent
awk '!x[$0]++'
```