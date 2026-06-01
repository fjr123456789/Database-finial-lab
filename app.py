from flask import Flask, render_template, request, redirect, url_for, flash, session
from datetime import datetime, timedelta
from flask_sqlalchemy import SQLAlchemy
import config
from sqlalchemy import text, MetaData, create_engine
from sqlalchemy.orm import DeclarativeBase
from models import db, Student, Admin, Book, BorrowRecord, ReservationRecord, OverdueRecord

app = Flask(__name__)
# 连接配置
app.config.from_object(config)

# 初始化数据库
db.init_app(app)


@app.context_processor
def inject_now():
    """将 now 函数注入到所有模板中"""
    return {'now': datetime.now}  # 注意：是 datetime.now，不是 datetime

# 创建跟路由，http://127.0.0.0:5000
@app.route('/')
def index():
    return render_template('index.html')


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


# ==================== 学生仪表盘（ORM方式）====================
@app.route('/student/dashboard')
def student_dashboard():
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    student_id = session['user_id']

    # 当前借阅
    current_borrows = BorrowRecord.query.filter_by(
        student_id=student_id, status='借阅中'
    ).all()

    # 借阅历史
    borrow_history = BorrowRecord.query.filter(
        BorrowRecord.student_id == student_id,
        BorrowRecord.status.in_(['已还', '逾期'])
    ).order_by(BorrowRecord.borrow_date.desc()).limit(10).all()

    # 预定记录
    reservations = ReservationRecord.query.filter_by(
        student_id=student_id, status='等待中'
    ).all()

    # 调用存储过程或函数获取总罚款
    # 方式1：使用SQLAlchemy执行原生SQL调用函数
    from sqlalchemy import text
    result = db.session.execute(
        text(
            "SELECT IFNULL(SUM(fine_amount), 0) AS total_fine FROM overdue_record WHERE student_id = :sid AND paid_status = FALSE"),
        {'sid': student_id}
    ).fetchone()
    total_fine = float(result[0]) if result else 0
    total_fine = float(result[0]) if result else 0

    return render_template('student/dashboard.html',
                           current_borrows=current_borrows,
                           borrow_history=borrow_history,
                           reservations=reservations,
                           total_fine=total_fine,
                           timedelta=timedelta)  # ✅ 添加这一行)


# ==================== 图书查询（ORM方式）====================
# ==================== 图书查询（分页版）====================
@app.route('/student/books')
def student_books():
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
@app.route('/student/borrow/<book_id>')
def borrow_book(book_id):
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    student_id = session['user_id']

    # 开启事务
    try:
        # 检查图书
        book = Book.query.get(book_id)
        if not book or book.available_count <= 0:
            flash('该书已借完', 'warning')
            return redirect(url_for('student_books'))

        # 检查逾期未还
        overdue_borrow = BorrowRecord.query.filter(
            BorrowRecord.student_id == student_id,
            BorrowRecord.status == '借阅中',
            BorrowRecord.due_date < datetime.now().date()
        ).first()

        if overdue_borrow:
            flash('请先还清逾期图书', 'danger')
            return redirect(url_for('student_dashboard'))

        # 检查借阅数量（最多5本）
        borrow_count = BorrowRecord.query.filter_by(
            student_id=student_id, status='借阅中'
        ).count()

        if borrow_count >= 5:
            flash('借书数量已达上限（5本）', 'warning')
            return redirect(url_for('student_books'))

        # 创建借阅记录（触发器会自动更新available_count）
        new_borrow = BorrowRecord(
            student_id=student_id,
            book_id=book_id,
            borrow_date=datetime.now().date(),
            due_date=datetime.now().date() + timedelta(days=30),
            status='借阅中'
        )

        db.session.add(new_borrow)
        db.session.commit()

        flash(f'成功借阅《{book.title}》', 'success')

    except Exception as e:
        db.session.rollback()
        flash(f'借书失败：{str(e)}', 'danger')

    return redirect(url_for('student_books'))


# ==================== 还书（调用存储过程）====================
@app.route('/student/return/<int:record_id>')
def return_book(record_id):
    if session.get('user_type') != 'student':
        return redirect(url_for('index'))

    from sqlalchemy import text

    try:
        # 调用存储过程
        db.session.execute(
            text("CALL ReturnBook(:record_id, :return_date)"),
            {'record_id': record_id, 'return_date': datetime.now().date()}
        )
        db.session.commit()
        flash('还书成功！', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'还书失败：{str(e)}', 'danger')

    return redirect(url_for('student_dashboard'))


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
        flash('您已预定过该书', 'info')
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
        expire_date=datetime.now().date() + timedelta(days=7),
        status='等待中'
    )

    db.session.add(new_reserve)
    db.session.commit()

    flash(f'成功预定《{book.title}》，请在7天内来馆取书', 'success')
    return redirect(url_for('student_books'))


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
@app.route('/admin/dashboard')
def admin_dashboard():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    total_books = Book.query.count()
    total_students = Student.query.count()
    active_borrows = BorrowRecord.query.filter_by(status='借阅中').count()

    # 计算逾期数量
    from sqlalchemy import text
    result = db.session.execute(
        text("SELECT COUNT(*) FROM borrow_record WHERE status = '借阅中' AND due_date < CURDATE()")
    ).fetchone()
    overdue_count = result[0] if result else 0

    return render_template('admin/dashboard.html',
                           total_books=total_books,
                           total_students=total_students,
                           active_borrows=active_borrows,
                           overdue_count=overdue_count)


# ==================== 图书管理（ORM方式）====================
@app.route('/admin/books')
def admin_books():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    books = Book.query.order_by().all()
    return render_template('admin/manage_books.html', books=books)


@app.route('/admin/book/add', methods=['POST'])
def add_book():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    new_book = Book(
        book_id=request.form['book_id'],
        title=request.form['title'],
        author=request.form.get('author', ''),
        publisher=request.form.get('publisher', ''),
        # category=request.form.get('category', ''),
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


# ==================== 学生管理（ORM方式）====================
@app.route('/admin/students')
def admin_students():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    students = Student.query.order_by().all()
    return render_template('admin/manage_students.html', students=students)


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
            flash(f'删除失败：{str(e)}', 'danger')

    return redirect(url_for('admin_students'))


# ==================== 借阅管理 ====================
@app.route('/admin/borrows')
def admin_borrows():
    if session.get('user_type') != 'admin':
        return redirect(url_for('index'))

    borrows = BorrowRecord.query.order_by(BorrowRecord.borrow_date.desc()).all()
    return render_template('admin/borrow_management.html', borrows=borrows)


# ==================== 退出登录 ====================
@app.route('/logout')
def logout():
    session.clear()
    flash('已退出登录', 'info')
    return redirect(url_for('index'))


if __name__ == '__main__':
    app.run(debug=True, port=5000, host='0.0.0.0')
