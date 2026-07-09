import re
import sys

filepath = sys.argv[1]
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

before = len(re.findall(r'cents_to_rub|rub_to_cents', content))

# WRITE: cents_to_rub($N) -> $N
content = re.sub(r'cents_to_rub\(\$(\d+)\)', r'$\1', content)

# READ: rub_to_cents(column_name) -> column_name for known money columns
# Handle simple columns and prefixed columns (p.amount, o.price_total, wt.amount)
# Match: rub_to_cents(tablename.columnname) -> tablename.columnname
content = re.sub(r'rub_to_cents\((\w+(?:\.\w+)?)\)', r'\1', content)

after = len(re.findall(r'cents_to_rub|rub_to_cents', content))
print(f'Before: {before} occurrences')
print(f'After: {after} occurrences')

remaining = [(i+1, line) for i, line in enumerate(content.splitlines()) if 'cents_to_rub' in line or 'rub_to_cents' in line]
if remaining:
    print('Remaining:')
    for n, l in remaining:
        print(f'  {n}: {l.strip()}')
else:
    print('All converters removed!')

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)