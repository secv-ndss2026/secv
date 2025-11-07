import re
import sys


def extract_deltas(filename):
    deltas = []
    with open(filename, 'r') as f:
        for line in f:
            match = re.match(r"\s*\((\d+\.\d+)\)", line)
            if match:
                deltas.append(float(match.group(1)))
    return deltas


def compute_average(values):
    if not values:
        return 0.0
    return sum(values) / len(values)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python avg_latency.py <candump_output.txt>")
        sys.exit(1)

    filename = sys.argv[1]
    deltas = extract_deltas(filename)
    #    print(deltas)
    avg = compute_average(deltas)

    print(f"Average latency: {avg * 1e6:.2f}")
