from flask import Flask, render_template, request, redirect, url_for, flash, session, send_from_directory
from datetime import datetime, timedelta, date
from flask_sqlalchemy import SQLAlchemy
import config
from flask_apscheduler import APScheduler
from werkzeug.utils import secure_filename
import os
from config import UPLOAD_FOLDER, MAX_CONTENT_LENGTH, ALLOWED_EXTENSIONS, UPLOAD_FOLDER_CONTENT

from sqlalchemy import text, MetaData, create_engine, func
from sqlalchemy.orm import DeclarativeBase
from models import db, Student, Admin, Book, BorrowRecord, ReservationRecord, OverdueRecordView, OverdueRecord

app = Flask(__name__)
# 连接配置
app.config.from_object(config)

# 定时任务配置
scheduler = APScheduler()
# 初始化数据库
db.init_app(app)

# 定时任务函数
def daily_overdue_check():
    """每天执行存储过程生成逾期记录"""
    with app.app_context():
        try:
            # 调用存储过程
            db.session.execute(text("CALL GenerateDailyOverdue()"))
            db.session.commit()
            print(f"[{datetime.now()}] 逾期记录已更新")
        except Exception as e:
            db.session.rollback()
            print(f"[{datetime.now()}] 更新逾期记录失败：{str(e)}")

# 配置定时任务（每天凌晨0点执行）
scheduler.add_job(
    id='daily_overdue_check',
    func=daily_overdue_check,
    trigger='cron',
    hour=0,
    minute=0
)

# 启动定时任务
scheduler.init_app(app)
scheduler.start()

# 确保上传目录存在
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS



# 注入模板变量
@app.context_processor
def inject_now():
    return {'now': datetime.now, 'timedelta': timedelta, 'date': date}

# 创建跟路由，http://127.0.0.0:5000
@app.route('/')
def index():
    books = Book.query.order_by(Book.book_id).all()  # 获取前6本图书
    return render_template('index.html', books=books)


# ==================== 学生注册（ORM方式）====================
@app.route('/student/register', methods=['GET', 'POST'])
def student_register():
    if request.method == 'POST':
        student_id = request.form.get('student_id')
        name = request.form.get('name')
        password = request.form.get('password')
        confirm_password = request.form.get('confirm_password')
        phone = request.form.get('phone')
        email = request.form.get('email')

        if not all([student_id, name, password]):
            flash('请填写所有必填字段', 'danger')
            return render_template('student/register.html')

        if password != confirm_password:
            flash('两次密码不一致', 'danger')
            return render_template('student/register.html')

        # 检查学号是否已存在
        existing = Student.query.get(student_id)
        if existing:
            flash('学号已被注册', 'danger')
            return render_template('student/register.html')

        # 创建新学生
        new_student = Student(
            student_id=student_id,
            name=name,
            password=password,
            phone=phone,
            email=email
        )

        try:
            db.session.add(new_student)
            db.session.commit()
            flash('注册成功！请登录', 'success')
            return redirect(url_for('student_login'))
        except Exception as e:
            db.session.rollback()
            flash(f'注册失败：{str(e)}', 'danger')

    return render_template('student/register.html')


# ==================== 学生登录（ORM方式）====================
@app.route('/student/login', methods=['GET', 'POST'])
def student_login():
    if request.method == 'POST':
        student_id = request.form.get('student_id')
        password = request.form.get('password')

        student = Student.query.filter_by(student_id=student_id, password=password).first()

        if student:
            session['user_id'] = student.student_id
            session['user_name'] = student.name
            session['user_type'] = 'student'
            flash(f'欢迎回来，{student.name}！', 'success')
            return redirect(url_for('student_dashboard'))
        else:
            flash('学号或密码错误', 'danger')

    return render_template('student/login.html')


# ==================== 学生工作台（ORM方式）====================

@app.route('/student/dashboard')
def student_dashboard():
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    # 更新逾期表
    db.session.execute(text("CALL GenerateDailyOverdue()"))
    db.session.commit()

    student_id = session['user_id']
    today = date.today()

    # 当前借阅
    current_borrows = BorrowRecord.query.filter(
        BorrowRecord.student_id == student_id,
        BorrowRecord.return_date.is_(None)
    ).all()

    student = Student.query.filter_by(student_id=student_id).first()
    # 当前逾期（未归还且超过应还日期）
    overdue_borrows = []
    for borrow in current_borrows:
        if borrow.borrow_date + timedelta(days=30) < today:
            # 添加逾期天数属性
            borrow.overdue_days = (today - (borrow.borrow_date + timedelta(days=30))).days
            overdue_borrows.append(borrow)


    # 历史借阅
    borrow_history = BorrowRecord.query.filter(
        BorrowRecord.student_id == student_id
    ).order_by(BorrowRecord.borrow_date.desc()).all()

    # 最近十条预约记录
    reservations = ReservationRecord.query.filter_by(
        student_id=student_id, status='等待中'
    ).order_by(ReservationRecord.reserve_id.desc()).limit(10).all()

    overdues = OverdueRecordView.query.filter(
        OverdueRecordView.student_id == student_id
    ).all()

    # 总罚款
    result = db.session.execute(
        text("SELECT IFNULL(SUM(fine_amount), 0) FROM overdue_record_view WHERE student_id = :sid AND paid_status = FALSE"),
        {'sid': student_id}
    ).fetchone()
    total_fine = float(result[0]) if result else 0

    return render_template('student/dashboard.html',
                           student = student,
                           current_borrows=current_borrows,
                           borrow_history=borrow_history,
                           reservations=reservations,
                           overdue_borrows=overdue_borrows,
                           total_fine=total_fine,
                           overdue_count=len(overdues),
                           timedelta=timedelta)


# 学生取消预约
@app.route('/student/cancel_reservation/<int:reserve_id>')
def cancel_reservation(reserve_id):
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    reservation = ReservationRecord.query.get(reserve_id)
    if not reservation:
        flash('预约记录不存在', 'danger')
        return redirect(url_for('student_dashboard'))

    if reservation.student_id != session['user_id']:
        flash('无权限操作', 'danger')
        return redirect(url_for('student_dashboard'))

    if reservation.status != '等待中':
        flash('该预约已无法取消', 'warning')
        return redirect(url_for('student_dashboard'))

    try:
        reservation.status = '已取消'
        db.session.commit()
        flash(f'已取消《{reservation.book.title}》的预约', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'取消失败：{str(e)}', 'danger')

    return redirect(url_for('student_dashboard'))

# ==================== 图书查询（ORM方式）====================
# ==================== 图书查询（分页版）====================
@app.route('/student/books')
def student_books():
    # 不是学生，跳转到主页
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    search = request.args.get('search', '')
    page = request.args.get('page', 1, type=int)  # 获取当前页码，默认第1页
    per_page = 10  # 每页显示10条

    query = Book.query

    if search:
        query = query.filter(
            db.or_(
                Book.title.contains(search),
                Book.author.contains(search)
            )
        )

    # 分页查询
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    books = pagination.items  # 当前页的图书
    total = pagination.total  # 总记录数
    pages = pagination.pages  # 总页数

    return render_template('student/books.html',
                           books=books,
                           search=search,
                           page=page,
                           pages=pages,
                           total=total)
# ==================== 借书（ORM + 事务）====================
# ==================== 借书（调用存储过程 - 使用text方式）====================
@app.route('/student/borrow/<book_id>')
def borrow_book(book_id):
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    # 获取来源页面参数，用于结束时重定向
    next_page = request.args.get('next', 'student_books')

    student_id = session['user_id']

    try:
        # 使用 text() 调用存储过程
        result = db.session.execute(
            text("CALL BorrowBook(:student_id, :book_id, @state, @message)"),
            {'student_id': student_id, 'book_id': book_id}
        )

        # 获取 OUT 参数
        result_state = db.session.execute(text("SELECT @state, @message")).fetchone()

        if result_state:
            p_state = result_state[0]
            p_message = result_state[1]
        else:
            p_state = 1
            p_message = '未知错误'

        db.session.commit()

        if p_state == 0:
            flash(p_message, 'success')
        else:
            flash(f'借书失败：{p_message}', 'danger')

    except Exception as e:
        db.session.rollback()
        flash(f'借书失败：{str(e)}', 'danger')

    return redirect(url_for(next_page))

# ==================== 还书（调用存储过程）====================
@app.route('/student/return/<int:record_id>')
def return_book(record_id):
    user_type = session.get('user_type')
    if user_type not in ['student', 'admin']:
        return redirect(url_for('index'))

    # 获取来源页面参数，用于结束时重定向
    next_page = request.args.get('next', 'student_dashboard')
    try:
        # 获取原生数据库连

        # 使用 text() 调用存储过程
        result = db.session.execute(
            text("CALL ReturnBook(:record_id, @state, @message)"),
            {'record_id': record_id}
        )
        # 获取 OUT 参数（第2和第3个参数）
        # 获取 OUT 参数
        result_state = db.session.execute(text("SELECT @state, @message")).fetchone()

        if result_state:
            p_state = result_state[0]
            p_message = result_state[1]
        else:
            p_state = 3
            p_message = '未知错误'

        db.session.commit()

        if p_state == 0:
            flash(p_message, 'success')
        else:
            flash(f'还书失败：{p_message}', 'danger')

    except Exception as e:
        flash(f'还书失败：{str(e)}', 'danger')

    return redirect(url_for(next_page))

# ==================== 预定图书（ORM方式）====================
@app.route('/student/reserve/<book_id>')
def reserve_book(book_id):
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    student_id = session['user_id']

    # 检查是否已预定
    existing = ReservationRecord.query.filter_by(
        student_id=student_id, book_id=book_id, status='等待中'
    ).first()

    if existing:
        flash('您已预定过该书', 'warning')
        return redirect(url_for('student_books'))

    book = Book.query.get(book_id)
    if not book:
        flash('图书不存在', 'danger')
        return redirect(url_for('student_books'))

    # 创建预定记录
    new_reserve = ReservationRecord(
        student_id=student_id,
        book_id=book_id,
        reserve_date=datetime.now().date(),
        status='等待中'
    )

    db.session.add(new_reserve)
    db.session.commit()

    flash(f'成功预定《{book.title}》，请在7天内来馆取书', 'success')
    return redirect(url_for('student_books'))

# 历史借阅
@app.route('/student/borrow_history')
def student_borrow_history():
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    student_id = session['user_id']
    page = request.args.get('page', 1, type=int)
    per_page = 20

    # 已归还的借阅记录
    query = BorrowRecord.query.filter(
        BorrowRecord.student_id == student_id
    ).order_by(BorrowRecord.borrow_date.desc())

    pagination = query.paginate(page=page, per_page=per_page, error_out=False)

    return render_template('student/borrow_history.html',
                           borrows=pagination.items,
                           page=pagination.page,
                           pages=pagination.pages,
                           total=pagination.total,
                           timedelta=timedelta)

# 历史逾期
@app.route('/student/overdue_history')
def student_overdue_history():
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    student_id = session['user_id']
    page = request.args.get('page', 1, type=int)
    per_page = 10

    # 逾期记录（通过 overdue_record 表关联）
    query = OverdueRecordView.query.filter(
        OverdueRecordView.student_id == student_id
    ).order_by(OverdueRecordView.overdue_id.desc())

    pagination = query.paginate(page=page, per_page=per_page, error_out=False)

    return render_template('student/overdue_history.html',
                           overdues=pagination.items,
                           page=pagination.page,
                           pages=pagination.pages,
                           total=pagination.total,
                           timedelta=timedelta)


# ==================== 管理员登录 ====================
@app.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    if request.method == 'POST':
        admin_id = request.form.get('admin_id')
        password = request.form.get('password')

        admin = Admin.query.filter_by(admin_id=admin_id, password=password).first()

        if admin:
            session['admin_id'] = admin.admin_id
            session['admin_name'] = admin.name
            session['user_type'] = 'admin'
            flash(f'欢迎，{admin.name}！', 'success')
            return redirect(url_for('admin_dashboard'))
        else:
            flash('账号或密码错误', 'danger')

    return render_template('admin/login.html')


# ==================== 管理员仪表盘 ====================
from datetime import date
from sqlalchemy import text


@app.route('/admin/dashboard')
def admin_dashboard():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    total_books = Book.query.count()
    total_students = Student.query.count()

    # 当前借阅：return_date 为空的记录
    active_borrows = BorrowRecord.query.filter(
        BorrowRecord.return_date.is_(None)
    ).all()

    # 逾期数量：使用原生 SQL
    today = date.today()
    result = db.session.execute(
        text("""
             SELECT COUNT(*)
             FROM borrow_record
             WHERE return_date IS NULL
               AND DATE_ADD(borrow_date, INTERVAL 30 DAY) < :today
             """),
        {'today': today}
    ).fetchone()
    overdue_count = result[0] if result else 0

    return render_template('admin/dashboard.html',
                           total_books=total_books,
                           total_students=total_students,
                           active_borrows=len(active_borrows),
                           current_borrows=active_borrows,
                           overdue_count=overdue_count)


# ==================== 图书管理（ORM方式）====================
@app.route('/admin/books')
def admin_books():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    page = request.args.get('page', 1, type=int)  # 获取当前页码，默认第1页
    per_page = 10  # 每页显示10条

    query = Book.query.order_by(Book.book_id)
        # 分页查询
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    books = pagination.items  # 当前页的图书
    total = pagination.total  # 总记录数
    pages = pagination.pages  # 总页数

    return render_template('admin/manage_books.html', books=books,total=total,pages=pages,page=page)


@app.route('/admin/book/add', methods=['POST'])
def add_book():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    new_book = Book(
        book_id=request.form['book_id'],
        title=request.form['title'],
        author=request.form.get('author', ''),
        publisher=request.form.get('publisher', ''),
        total_count=int(request.form['total_count']),
        available_count=int(request.form['total_count'])
    )

    try:
        db.session.add(new_book)
        db.session.commit()
        flash('图书添加成功', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'添加失败：{str(e)}', 'danger')

    return redirect(url_for('admin_books'))


@app.route('/admin/book/delete/<book_id>')
def delete_book(book_id):
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    book = Book.query.get(book_id)
    if book:
        try:
            db.session.delete(book)
            db.session.commit()
            flash('图书已删除', 'success')
        except Exception as e:
            db.session.rollback()
            flash(f'删除失败：{str(e)}', 'danger')

    return redirect(url_for('admin_books'))



# 修改图书信息
@app.route('/admin/book/edit/<book_id>', methods=['GET', 'POST'])
def edit_book(book_id):
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    book = Book.query.get(book_id)
    if not book:
        flash('图书不存在', 'danger')
        return redirect(url_for('admin_books'))

    if request.method == 'POST':
        # 获取表单数据
        title = request.form.get('title')
        author = request.form.get('author')
        publisher = request.form.get('publisher')
        total_count = request.form.get('total_count')

        # 更新基本信息
        if title:
            book.title = title
        if author:
            book.author = author
        if publisher:
            book.publisher = publisher
        if total_count:
            new_total = int(total_count)
            # 如果总数量变化，调整可借数量
            diff = new_total - book.total_count
            book.total_count = new_total
            book.available_count += diff
            if book.available_count < 0:
                book.available_count = 0

        # 处理封面上传
        if 'cover_image' in request.files:
            file = request.files['cover_image']
            if file and file.filename and allowed_file(file.filename):
                # 生成安全文件名
                filename = secure_filename(f"{book_id}_{file.filename}")
                filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                file.save(filepath)

                # 删除旧封面
                if book.cover_image:
                    old_path = os.path.join('static', book.cover_image)
                    if os.path.exists(old_path):
                        os.remove(old_path)

                # 存储相对路径
                book.cover_image = f'uploads/covers/{filename}'
                flash('封面更新成功', 'success')
            elif file and file.filename:
                flash('不支持的文件格式，请上传 PNG、JPG、JPEG 或 GIF', 'danger')

        # ========== 处理电子书上传==========
        if 'ebook_file' in request.files:
            ebook_file = request.files['ebook_file']
            if ebook_file and ebook_file.filename and ebook_file.filename.strip():
                # 检查文件扩展名
                ext = ebook_file.filename.rsplit('.', 1)[1].lower() if '.' in ebook_file.filename else ''
                allowed_ebook_extensions = {'pdf'}

                if ext in allowed_ebook_extensions:
                    # 生成新文件名（使用时间戳避免重名）
                    new_filename = f"ebook_{book_id}_{int(datetime.now().timestamp())}.{ext}"
                    # 保存到 static/uploads/content 目录
                    upload_dir = UPLOAD_FOLDER_CONTENT
                    os.makedirs(upload_dir, exist_ok=True)
                    filepath = os.path.join(upload_dir, new_filename)
                    ebook_file.save(filepath)

                    # 删除旧电子书
                    if book.content:
                        old_path = os.path.join('static', book.content)
                        if os.path.exists(old_path):
                            os.remove(old_path)

                    # 存储相对路径（相对于 static 目录）
                    book.content = f'uploads/content/{new_filename}'
                    flash('电子书上传成功', 'success')
                else:
                    flash('不支持的文件格式，请上传 PDF', 'danger')
        try:
            db.session.commit()
            flash(f'图书《{book.title}》信息修改成功', 'success')
            return redirect(url_for('admin_books'))
        except Exception as e:
            db.session.rollback()
            flash(f'修改失败：{str(e)}', 'danger')

    return render_template('admin/edit_book.html', book=book)

# ==================== 学生管理（ORM方式）====================
@app.route('/admin/students')
def admin_students():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    page = request.args.get('page', 1, type=int)  # 获取当前页码，默认第1页
    per_page = 10  # 每页显示10条

    query = Student.query.order_by()
        # 分页查询
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    students = pagination.items  # 当前页的图书
    total = pagination.total  # 总记录数
    pages = pagination.pages  # 总页数
    return render_template('admin/manage_students.html', students=students,total=total,pages=pages,page=page)


@app.route('/admin/student/add', methods=['POST'])
def add_student():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    new_student = Student(
        student_id=request.form['student_id'],
        name=request.form['name'],
        password=request.form['password'],
        phone=request.form.get('phone', ''),
        email=request.form.get('email', '')
    )

    try:
        db.session.add(new_student)
        db.session.commit()
        flash('学生添加成功', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'添加失败：{str(e)}', 'danger')

    return redirect(url_for('admin_students'))


@app.route('/admin/student/delete/<student_id>')
def delete_student(student_id):
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    student = Student.query.get(student_id)
    if student:
        try:
            db.session.delete(student)
            db.session.commit()
            flash('学生已删除', 'success')
        except Exception as e:
            db.session.rollback()
            flash(f'删除失败：', 'danger')

    return redirect(url_for('admin_students'))


# ==================== 学生信息修改 ====================
@app.route('/admin/student/edit/<student_id>', methods=['GET', 'POST'])
def edit_student(student_id):
    user_type = session.get('user_type')
    if user_type not in ['student', 'admin']:
        return redirect(url_for('index'))

    if user_type == 'student':
        next_page = 'student_dashboard'
    else:
        next_page = 'admin_students'

    student = Student.query.get(student_id)
    if not student:
        flash('学生不存在', 'danger')
        return redirect(url_for('admin_students'))

    if request.method == 'POST':
        # 获取表单数据（学号不可修改，所以不处理）
        name = request.form.get('name')
        phone = request.form.get('phone')
        email = request.form.get('email')
        password = request.form.get('password')

        # 更新信息
        if name:
            student.name = name
        if phone:
            student.phone = phone
        if email:
            student.email = email
        if password:
            student.password = password  # 实际应用中应该加密

        # 处理头像上传
        if 'image' in request.files:
            file = request.files['image']
            if file and file.filename and allowed_file(file.filename):
                # 生成安全文件名
                filename = secure_filename(f"{student_id}_{file.filename}")
                filepath = os.path.join(app.config['UPLOAD_FOLDER_IMAGE'], filename)
                file.save(filepath)

                # 删除旧头像
                if student.image:
                    old_path = os.path.join('static', student.image)
                    if os.path.exists(old_path):
                        os.remove(old_path)

                # 存储相对路径
                student.image = f'uploads/image/{filename}'
                flash('头像更新成功', 'success')
            elif file and file.filename:
                flash('不支持的文件格式，请上传 PNG、JPG、JPEG 或 GIF', 'danger')

        try:
            db.session.commit()
            flash(f'学生 {student.name} 信息修改成功', 'success')
            return redirect(url_for(next_page))
        except Exception as e:
            db.session.rollback()
            flash(f'修改失败：{str(e)}', 'danger')

    return render_template('admin/edit_student.html', student=student)

# ==================== 借阅管理 ====================
@app.route('/admin/borrows')
def admin_borrows():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    search = request.args.get('search', '')
    status_filter = request.args.get('status', '')
    page = request.args.get('page', 1, type=int)
    per_page = 10

    query = BorrowRecord.query

    if search:
        query = query.filter(
            db.or_(
                BorrowRecord.student.has(Student.name.contains(search)),
                BorrowRecord.student_id.contains(search),
                BorrowRecord.book.has(Book.title.contains(search))
            )
        )

    # 按状态筛选（使用 return_date 判断）
    if status_filter:
        if status_filter == '借阅中':
            query = query.filter(BorrowRecord.return_date.is_(None))
        elif status_filter == '已还':
            query = query.filter(BorrowRecord.return_date.is_not(None))
        elif status_filter == '逾期':
            # 逾期：未归还 且 borrow_date + 30 < 今天
            query = query.filter(
                BorrowRecord.return_date.is_(None),
                BorrowRecord.borrow_date + timedelta(days=30) < date.today()
            )

    pagination = query.order_by(BorrowRecord.borrow_date.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )

    return render_template('admin/borrow_management.html',
                           borrows=pagination.items,
                           total=pagination.total,
                           pages=pagination.pages,
                           page=page)

# 管理员查看所有预约
@app.route('/admin/reservations')
def admin_reservations():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    status_filter = request.args.get('status', '')
    page = request.args.get('page', 1, type=int)
    per_page = 10

    query = ReservationRecord.query
    if status_filter:
        query = query.filter(ReservationRecord.status == status_filter)

    query = query.order_by(ReservationRecord.reserve_date.desc())
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)

    return render_template('admin/reservations.html',
                           reservations=pagination.items,
                           status=status_filter,
                           page=pagination.page,
                           pages=pagination.pages,
                           total=pagination.total)


# 删除预约记录（彻底删除）
@app.route('/admin/delete_reservation/<int:reserve_id>')
def delete_reservation(reserve_id):
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    reservation = ReservationRecord.query.get(reserve_id)
    if not reservation:
        flash('预约记录不存在', 'danger')
        return redirect(url_for('admin_reservations'))

    try:
        db.session.delete(reservation)
        db.session.commit()
        flash(
            f'已删除预约记录）',
            'success')
    except Exception as e:
        db.session.rollback()
        flash(f'删除失败：{str(e)}', 'danger')

    return redirect(url_for('admin_reservations'))


# 管理员查看所有逾期罚款
@app.route('/admin/overdues')
def admin_overdues():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    paid_status = request.args.get('paid_status', '')
    page = request.args.get('page', 1, type=int)
    per_page = 10

    query = OverdueRecordView.query
    if paid_status == 'unpaid':
        query = query.filter(OverdueRecordView.paid_status == False)
    elif paid_status == 'paid':
        query = query.filter(OverdueRecordView.paid_status == True)

    query = query.order_by(OverdueRecordView.overdue_id.desc())
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)

    # 统计未缴罚款总额
    total_unpaid = db.session.query(db.func.sum(OverdueRecordView.fine_amount)).filter(
        OverdueRecordView.paid_status == False
    ).scalar() or 0

    return render_template('admin/overdues.html',
                           overdues=pagination.items,
                           paid_status=paid_status,
                           total_unpaid=float(total_unpaid),
                           page=pagination.page,
                           pages=pagination.pages,
                           total=pagination.total)


# 管理员标记罚款已缴纳（线下缴费）
@app.route('/admin/mark_paid/<int:overdue_id>')
def mark_paid(overdue_id):
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    overdue = OverdueRecordView.query.get(overdue_id)
    if not overdue:
        flash('记录不存在', 'danger')
        return redirect(url_for('admin_overdues'))

    if overdue.paid_status:
        flash('该罚款已缴纳', 'warning')
        return redirect(url_for('admin_overdues'))

    if not overdue.return_date:
        flash('尚未还书', 'warning')
        return redirect(url_for('admin_overdues'))

    try:
        overdue.paid_status = True
        overdue.paid_date = datetime.now().date()
        db.session.commit()
        flash(f'已标记成功', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'操作失败：{str(e)}', 'danger')

    return redirect(url_for('admin_overdues'))


# ==================== 退出登录 ====================
@app.route('/logout')
def logout():
    session.clear()
    flash('已退出登录', 'warning')
    return redirect(url_for('index'))


if __name__ == '__main__':
    app.run(debug=True, port=5000, host='0.0.0.0')
