-- 1. 把 root 用户的 host 改成 %（允许任何地址连接）
UPDATE mysql.user SET host = '%' WHERE user = 'root';

-- 2. 刷新权限
FLUSH PRIVILEGES;
SELECT host, user FROM mysql.user;
