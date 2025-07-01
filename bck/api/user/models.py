from tkinter import N
from django.db import models
from django.contrib.auth.models import AbstractUser
from .managers import CustomUserManager
# Create your models here.
class CustomUser(AbstractUser):
    name = models.CharField(max_length=255,default='Anonymous',null=True,blank=True)
    username = None
    phone = models.CharField(max_length=15, unique=True, null=False, blank=False)  # Make phone unique and required
    USERNAME_FIELD = 'phone'  # Use phone as the login field
    REQUIRED_FIELDS = []
    session_token = models.CharField(max_length=10 , default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    objects = CustomUserManager()
    def __str__(self):
        return self.phone