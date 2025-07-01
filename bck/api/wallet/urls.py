# urls.py
from django.urls import path , include
from .views import WalletViewSet  
from rest_framework import routers 
router = routers.DefaultRouter()
router.register(r'wallets', WalletViewSet, basename='wallet')
# router.register(r'wallet-transactions', WalletTransactionViewSet, basename='wallet-transaction')
 
urlpatterns = [
    path("", include(router.urls) )
    
]
