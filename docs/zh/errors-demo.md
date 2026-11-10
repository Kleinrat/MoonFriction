# 四种错误：检查、修复、再检查

先完成[入门准备](getting-started.md)。所有修改只在临时副本中进行，仓库坏包保持不变。命令退出1表示预期的数据错误。每个代码块的预期退出码由 CI 自动验证。

<!-- test: exit=0 -->
```sh
export MOONFRICTION_DEMO="${MOONFRICTION_DEMO:-$(mktemp -d)}"
```

## type：预期 type

<!-- test: exit=0 -->
```sh
cp -R examples/broken-type "$MOONFRICTION_DEMO/type"
```

<!-- test: exit=1 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/type/datapackage.json"
```

修复副本中的值，再检查。主键重复样例也可能伴随外键错误。

<!-- test: exit=0 -->
```sh
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["MOONFRICTION_DEMO"]) / "type/orders.csv"
p.write_text(p.read_text().replace('two', '2'), encoding="utf-8")
PY
```

<!-- test: exit=0 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/type/datapackage.json"
```

## primary-key：预期 primary-key-duplicate

<!-- test: exit=0 -->
```sh
cp -R examples/broken-primary-key "$MOONFRICTION_DEMO/primary-key"
```

<!-- test: exit=1 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/primary-key/datapackage.json"
```

修复副本中的值，再检查。主键重复样例也可能伴随外键错误。

<!-- test: exit=0 -->
```sh
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["MOONFRICTION_DEMO"]) / "primary-key/products.csv"
p.write_text(p.read_text().replace('1,钢笔', '2,钢笔'), encoding="utf-8")
PY
```

<!-- test: exit=0 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/primary-key/datapackage.json"
```

## foreign-key：预期 foreign-key

<!-- test: exit=0 -->
```sh
cp -R examples/broken-foreign-key "$MOONFRICTION_DEMO/foreign-key"
```

<!-- test: exit=1 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/foreign-key/datapackage.json"
```

修复副本中的值，再检查。主键重复样例也可能伴随外键错误。

<!-- test: exit=0 -->
```sh
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["MOONFRICTION_DEMO"]) / "foreign-key/orders.csv"
p.write_text(p.read_text().replace('999', '1'), encoding="utf-8")
PY
```

<!-- test: exit=0 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/foreign-key/datapackage.json"
```

## header：预期 header

<!-- test: exit=0 -->
```sh
cp -R examples/broken-header "$MOONFRICTION_DEMO/header"
```

<!-- test: exit=1 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/header/datapackage.json"
```

修复副本中的值，再检查。主键重复样例也可能伴随外键错误。

<!-- test: exit=0 -->
```sh
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ["MOONFRICTION_DEMO"]) / "header/products.csv"
p.write_text(p.read_text().replace('id,wrong', 'id,title'), encoding="utf-8")
PY
```

<!-- test: exit=0 -->
```sh
node scripts/explain.mjs "$MOONFRICTION_DEMO/header/datapackage.json"
```

所有修复完成后可自行删除临时副本。教程不会自动清洗你的源数据。
