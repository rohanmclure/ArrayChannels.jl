import os
import csv
import uuid
import re
from datetime import datetime as dt
from collections import namedtuple

os.system("make ping_pong")

mpi_pp = "mpirun -np 2 example/ping_pong"
ac_pp = "julia example/ping_pong_array_channels.jl"
jl_pp = "julia example/ping_pong.jl"

tests = [mpi_pp, ac_pp, jl_pp]

assert os.path.exists("example/benchmarks.csv")

BenchType = None
bench_marks = []

with open("example/benchmarks.csv", 'r') as bench_file:
    reader = csv.reader(bench_file)
    for row in reader:
        if not BenchType:
            BenchType = namedtuple(typename="BenchType", field_names=row)
            continue

        if row:
            bench_marks.append(BenchType(*row))

ResultType = namedtuple(typename="ResultType", field_names=(list(BenchType._fields) + ["mpi_pp", "ac_pp", "jl_pp"]))

results = []

for e in bench_marks:
    new_result = list(e)
    for t in tests:
        temp = uuid.uuid4()
        cmd = "%s %d %d > /tmp/%s" % (t, int(e.iterations), int(e.vector_sz), temp)
        print(cmd)
        while os.system(cmd): pass
        with open("/tmp/%s" % temp, 'r') as log_file:
            while True:
                line = log_file.readline()
                match = re.match(r'([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)[\s]?MB\/s', line)
                if match:
                    new_result.append(match.group(1))
                    break
    results.append(ResultType(*new_result))

if not os.path.isdir('results'): os.mkdir('results')
with open('results/results-%s' % dt.now(), 'w') as result_file:
    writer = csv.writer(result_file)
    writer.writerow(ResultType._fields)
    for r in results:
        writer.writerow(r)
