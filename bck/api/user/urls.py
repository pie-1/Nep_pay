from unittest.mock import patch
from rest_framework import routers
from . import views
from django.urls import path, include
from rest_framework_simplejwt.views import TokenObtainPairView , TokenRefreshView
router = routers.DefaultRouter()
router.register(r'',views.UserViewSet)

urlpatterns = [
    path('login/',TokenObtainPairView.as_view() , name='token_obtain_pair'),
    path('refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('',include(router.urls))
]