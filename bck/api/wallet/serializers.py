from rest_framework import serializers
from .models import Wallet

class WalletSerializer(serializers.HyperlinkedModelSerializer):
    user = serializers.HyperlinkedRelatedField(
        view_name='customuser-detail',
        read_only=True
    )

    class Meta:
        model = Wallet
        fields = ['url', 'user', 'balance', 'updated_at']