from django.shortcuts import render

# Create your views here.
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated , AllowAny
from api.user.serializers import UserSerializer
from .models import Wallet

class WalletViewSet(viewsets.ModelViewSet):
    permission_classes_by_action = {'create' : [AllowAny]}
    queryset = Wallet.objects.all().order_by('id')
    serializer_class = UserSerializer

    def get_permissions(self):
        try:
            return [permission() for permission in self.permission_classes_by_action[self.action]]
        except KeyError:
            return [permission() for permission in self.permission_classes]