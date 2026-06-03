import os
SQLALCHEMY_DATABASE_URI = 'mysql+mysqldb://root:123456@localhost:3306/finial_lab?charset=utf8mb4'
SQLALCHEMY_TRACK_MODIFICATION = True
SECRET_KEY = '123456'


# 获取当前文件所在目录的绝对路径
BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# 文件上传配置
UPLOAD_FOLDER = 'static/uploads/covers'
UPLOAD_FOLDER_IMAGE = 'static/uploads/image'
UPLOAD_FOLDER_CONTENT = 'static/uploads/content'
MAX_CONTENT_LENGTH = 16 * 1024 * 1024

# 允许的文件扩展名
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}