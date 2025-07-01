from tkinter import N
from django.db import models
from django.contrib.auth.models import AbstractUser
# Create your models here.
class CustomUser(AbstractUser):
    name = models.CharField(max_length=255,default='Anonymous',null=True,blank=True)
    email = models.EmailField(max_length=255, null=True, blank=True , unique=True)  # Not unique, not required for login
    username = None
    phone = models.CharField(max_length=15, unique=True, null=False, blank=False)  # Make phone unique and required
    USERNAME_FIELD = 'phone'  # Use phone as the login field
    REQUIRED_FIELDS = []
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
