#!/usr/bin/env bash
# show_lmbench_results.sh
# - Adds a METRICS box for "Metric: value unit" lines (Simple read/open/write).
# Usage:
#   ./show_lmbench_results.sh results.txt [more.txt ...]

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <lmbench_result.txt> [more_results.txt ...]" >&2
  exit 1
fi

# Hide noisy meta sections. Set to empty "" to show everything.
SKIP_SECTIONS="LMBENCH_VER,BENCHMARK_HARDWARE,BENCHMARK_OS,DISKS,DISK_DESC,INFO,FILE,FSDIR,FASTMEM,FAST,ENOUGH,ENABLED"

for file in "$@"; do
  [ -f "$file" ] || { echo "Error: '$file' not found" >&2; continue; }

  awk -v SKIP="$SKIP_SECTIONS" -v FNAME="$(basename "$file")" '
  function trim(s){ sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
  function in_skip(sec,   n,a,i){ n=split(SKIP,a,","); for(i=1;i<=n;i++) if (sec==a[i]) return 1; return 0 }
  function is_numeric(t){ return (t ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) }
  function pad_right(s,w,  n){ n=w-length(s); if(n<0)n=0; return s sprintf("%" n "s","") }
  function pad_left(s,w,   n){ n=w-length(s); if(n<0)n=0; return sprintf("%" n "s","") s }

  # 2-column table helpers
  function hline2(w1,w2,    i,s){ s="+"; for(i=0;i<w1+2;i++) s=s"-"; s=s"+"; for(i=0;i<w2+2;i++) s=s"-"; s=s"+"; return s }
  function title2(title, total,  inside, s){
    inside = total-2; if (inside<0) inside=0;
    if (length(title) > inside) title = substr(title,1,inside)
    s="|" " " pad_right(title, inside) " " "|"; return s
  }
  function print_table2(sec, hdr1, hdr2,   r,w1,w2,total) {
    if (!(sec in rows)) return
    w1 = length(hdr1); w2 = length(hdr2)
    for (r=1; r<=rows[sec]; r++) {
      if (length(col1[sec,r]) > w1) w1 = length(col1[sec,r])
      if (length(col2[sec,r]) > w2) w2 = length(col2[sec,r])
    }
    total = (w1+2) + (w2+2) + 3
    print "+" sprintf("%" (total-1) "s","") "+"
    print title2(" " FNAME " :: [" sec "] ", total)
    print hline2(w1,w2)
    print "|" " " pad_right(hdr1, w1) " " "|" " " pad_right(hdr2, w2) " " "|"
    print hline2(w1,w2)
    for (r=1; r<=rows[sec]; r++) {
      c1 = (col1[sec,r] == "" ? "" : col1[sec,r])
      c2 = (col2[sec,r] == "" ? "" : col2[sec,r])
      printf("| %s | %s |\n", pad_right(c1, w1), (is_numeric(c2) ? pad_left(c2, w2) : pad_right(c2, w2)))
    }
    print hline2(w1,w2) "\n"
  }
  function flush_section(sec,  hdr1,hdr2){
    if (!(sec in rows)) return
    if (index(titles[sec], "bandwidth"))      { hdr1="Size"; hdr2="MB/s" }
    else if (index(titles[sec], "latency"))   { hdr1="Operation/Size"; hdr2="Latency (us)" }
    else if (index(titles[sec], "mmap") || index(titles[sec],"file")) { hdr1="Case/Size"; hdr2="Result" }
    else                                      { hdr1="Key/Size"; hdr2="Value" }
    print_table2(sec, hdr1, hdr2)
    delete rows[sec]
    for (i=1;i<=rowbuf[sec];i++){ delete col1[sec,i]; delete col2[sec,i] }
    rowbuf[sec]=0
  }

  # 3-column METRICS helpers
  function hline3(w1,w2,w3, i,s){ s="+"; for(i=0;i<w1+2;i++) s=s"-"; s=s"+"; for(i=0;i<w2+2;i++) s=s"-"; s=s"+"; for(i=0;i<w3+2;i++) s=s"-"; s=s"+"; return s }
  function title3(title,total,  inside,s){
    inside = total-2; if (inside<0) inside=0;
    if (length(title) > inside) title = substr(title,1,inside)
    s="|" " " pad_right(title, inside) " " "|"; return s
  }
  function print_metrics(   i,w1,w2,w3,total) {
    if (mcount==0) return
    w1=6; w2=5; w3=4
    for (i=1;i<=mcount;i++) {
      if (length(mname[i])>w1) w1=length(mname[i])
      if (length(mval[i]) >w2) w2=length(mval[i])
      if (length(munit[i])>w3) w3=length(munit[i])
    }
    total = (w1+2)+(w2+2)+(w3+2)+4
    print "+" sprintf("%" (total-1) "s","") "+"
    print title3(" " FNAME " :: [METRICS] ", total)
    print hline3(w1,w2,w3)
    print "|" " " pad_right("Metric", w1) " " "|" " " pad_right("Value", w2) " " "|" " " pad_right("Unit", w3) " " "|"
    print hline3(w1,w2,w3)
    for (i=1;i<=mcount;i++) {
      printf("| %s | %s | %s |\n",
             pad_right(mname[i], w1),
             pad_left(mval[i], w2),
             pad_right(munit[i], w3))
    }
    print hline3(w1,w2,w3) "\n"
  }

  BEGIN {
    print ""
    print "+==============================================================+"
    print "|                 LMBENCH RESULTS (pretty view)                |"
    print "+==============================================================+"
    print ""
    current=""; mcount=0
  }

  /^[[:space:]]*$/ { next }
  /^[-=]{5,}$/    { next }

  # Key:Value metric lines (captures Simple read/open/write, syscall, stat, ...)
  # e.g., "Simple read: 2.31 microseconds"
  /^[^#\[][^:]*:[[:space:]].*$/ {
    left=$0
    sub(/:.*/,"", left)         # left of colon
    right=$0
    sub(/^[^:]*:[[:space:]]*/,"", right)  # right of colon
    left=trim(left); right=trim(right)
    # split right into first numeric (value) + rest (unit)
    val=""; unit=""
    if (match(right, /[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?/)) {
      val = substr(right, RSTART, RLENGTH)
      unit = trim(substr(right, RSTART+RLENGTH))
    } else {
      val = right
      unit = ""
    }
    mname[++mcount]=left; mval[mcount]=val; munit[mcount]=unit
    next
  }

  # Section header like [ALL], [LINE_SIZE], etc.
  /^\[[^]]+\][[:space:]]*$/ {
    sec=$0; gsub(/[\[\]]/,"",sec); sec=trim(sec)
    if (current != "" && (current in rows)) flush_section(current)
    current=sec
    next
  }

  # body lines (arrays, numeric tables)
  {
    line=$0
    gsub(/\]/,"",line)
    gsub(/[[:space:]]+/, " ", line)
    line=trim(line)
    if (line=="") next

    # human title lines inside a section
    if (line ~ /[A-Za-z]/ && !is_numeric(line)) {
      titles[current] = (titles[current] ? titles[current] " " : "") line
      next
    }

    sec = (current=="" ? "GLOBAL" : current)
    if (in_skip(sec)) next

    n=split(line, f, " ")
    if (n==1) {
      rows[sec]++; col1[sec,rows[sec]]=f[1]; col2[sec,rows[sec]]=""
    } else {
      lastn=""; lasti=0
      for (i=n; i>=1; i--) if (is_numeric(f[i])) { lastn=f[i]; lasti=i; break }
      if (lasti==2 && is_numeric(f[1])) {
        rows[sec]++; col1[sec,rows[sec]]=f[1]; col2[sec,rows[sec]]=f[2]
      } else if (lasti>0) {
        lbl=f[1]; for (i=2; i<lasti; i++) lbl=lbl " " f[i]
        rows[sec]++; col1[sec,rows[sec]]=trim(lbl); col2[sec,rows[sec]]=lastn
      } else {
        rows[sec]++; col1[sec,rows[sec]]=f[1]; col2[sec,rows[sec]]=f[2]
      }
    }
  }

  END {
    # print metrics first
    print_metrics()

    # then flush last section or GLOBAL table(s)
    if (current != "" && (current in rows)) flush_section(current)
    else if ("GLOBAL" in rows) flush_section("GLOBAL")
  }
  ' "$file"

done
