from decimal import Decimal

from django.contrib.auth.base_user import BaseUserManager
from django.contrib.auth.models import AbstractUser
from django.core.validators import MaxValueValidator, MinValueValidator, RegexValidator
from django.db import models
from django.db.models import Q



phone_number_validator = RegexValidator(
    regex=r"^010[0-9]{8}$",
    message="전화번호는 하이픈 없이 01012341234 형식이어야 합니다.",
)


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create_user(self, username, password, **extra_fields):
        if not username:
            raise ValueError("The given username must be set")

        user = self.model(username=username, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, username, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(username, password, **extra_fields)

    def create_superuser(self, username, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)

        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")

        return self._create_user(username, password, **extra_fields)


class User(AbstractUser):
    class GenderChoices(models.TextChoices):
        MALE = "M", "남"
        FEMALE = "F", "여"

    # 이메일 로그인 제거, username 로그인 사용
    email = None
    first_name = None
    last_name = None
    
    username = models.CharField(max_length=150, unique=True)
    user_real_name = models.CharField(max_length=50)
    nickname = models.CharField(max_length=20, blank=True, null=True)
    phone_number = models.CharField(
        max_length=11,
        unique=True,
        validators=[phone_number_validator],
    )
    gender = models.CharField(
        max_length=1,
        choices=GenderChoices.choices,
    )
    profile_img_url = models.ImageField(
        upload_to="profiles/%Y/%m/%d/",
        max_length=500,
        blank=True,
        null=True,
    )
    
    fcm_token = models.CharField(max_length=255, blank=True, null=True)

    trust_score = models.DecimalField(
        max_digits=3,
        decimal_places=1,
        default=Decimal("36.5"),
        validators=[
            MinValueValidator(Decimal("0.0")),
            MaxValueValidator(Decimal("99.9")),
        ],
    )
    penalty_points = models.PositiveIntegerField(default=0)
    is_suspended = models.BooleanField(default=False)
    suspended_until = models.DateTimeField(blank=True, null=True)

    is_warning_active = models.BooleanField(default=False)
    successful_streak_count = models.PositiveIntegerField(default=0)
    last_score_updated_at = models.DateTimeField(blank=True, null=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = "username"
    REQUIRED_FIELDS = ["nickname", "user_real_name", "phone_number", "gender"]

    objects = UserManager()

    class Meta(AbstractUser.Meta):
        constraints = [
            models.CheckConstraint(
                condition=Q(trust_score__gte=0.0) & Q(trust_score__lte=99.9),
                name="accounts_user_trust_score_range",
            ),
            models.CheckConstraint(
                condition=Q(penalty_points__gte=0),
                name="accounts_user_penalty_points_nonnegative",
            ),
            models.CheckConstraint(
                condition=Q(successful_streak_count__gte=0),
                name="accounts_user_successful_streak_nonnegative",
            ),
            models.CheckConstraint(
                condition=Q(gender__in=["M", "F"]),
                name="accounts_user_gender_valid",
            ),
        ]

    def __str__(self):
        return self.username


class WithdrawalBlock(models.Model):
    class StatusChoices(models.TextChoices):
        ACTIVE = "ACTIVE", "ACTIVE"
        EXPIRED = "EXPIRED", "EXPIRED"
        RELEASED = "RELEASED", "RELEASED"

    phone_number = models.CharField(
        max_length=11,
        validators=[phone_number_validator],
        db_index=True,
    )
    blocked_until = models.DateTimeField()
    trust_score_at_withdrawal = models.DecimalField(
        max_digits=3,
        decimal_places=1,
        validators=[
            MinValueValidator(Decimal("0.0")),
            MaxValueValidator(Decimal("99.9")),
        ],
    )
    reason = models.CharField(max_length=100)
    status = models.CharField(
        max_length=20,
        choices=StatusChoices.choices,
        default=StatusChoices.ACTIVE,
    )
    withdrawn_user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="withdrawal_blocks",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["phone_number", "status"]),
        ]
        constraints = [
            models.CheckConstraint(
                condition=Q(trust_score_at_withdrawal__gte=0.0)
                & Q(trust_score_at_withdrawal__lte=99.9),
                name="accounts_withdrawalblock_trust_score_range",
            ),
        ]

    def __str__(self):
        return f"{self.phone_number} / {self.status} / until {self.blocked_until}"