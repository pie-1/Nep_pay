from unittest.mock import patch
from rest_framework import routers
from . import views
from django.urls import path, include
router = routers.DefaultRouter()
router.register(r'',views.UserViewSet)

urlpatterns = [
    path('login/',views.signin , name='signin'),
    path('logout/<int:id>/',views.signout , name='signout'),
    path('create_superuser/' , views.CreateSuperuserView.as_view() , name = 'create_superuser'),
    path('',include(router.urls))
]