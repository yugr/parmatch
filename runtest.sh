#!/bin/sh -e

cd `dirname $0`

tmp=$(mktemp)

trap "rm -f $tmp" EXIT

fail=0
for d in tests/*; do
  if test -d $d; then
    out=$d.out
    err=$d.err
    echo "Testing $d..."
    ./parmatch.pl $d >$tmp.out 2>$tmp.err
    if ! diff -q $d/out.txt $tmp.out; then
      echo >&2 "$d: stdout comparison failed:"
      diff -u $d/out.txt $tmp.out || true
      fail=1
    fi
    if test -f $d/err.txt; then
      stderr=$d/err.txt
    else
      stderr=/dev/null
    fi
    if ! diff -q $stderr $tmp.err; then
      echo >&2 "$d: stderr comparison failed"
      diff -u $stderr $tmp.err || true
      fail=1
    fi
  fi
done

if test $fail = 0; then
  echo SUCCEEDED
else
  echo FAILED
fi

exit $fail
