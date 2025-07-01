from rest_framework import serializers
from django.contrib.auth.hashers import make_password
from .models import CustomUser
import logging

logger = logging.getLogger(__name__)

class UserSerializer(serializers.HyperlinkedModelSerializer):

    def create(self, validated_data):
        print("✅ [DEBUG] validated_data passed to serializer.create():", validated_data)
        logger.debug("✅ [DEBUG] validated_data passed to serializer.create(): %s", validated_data)

        password = validated_data.pop('password', None)
        instance = self.Meta.model(**validated_data)

        if password is not None:
            instance.set_password(password)
        instance.save()

        return instance

    def update(self, instance, validated_data):
        print("✅ [DEBUG] validated_data passed to serializer.update():", validated_data)
        for attr, value in validated_data.items():
            if attr == 'password':
                instance.set_password(value)
            else:
                setattr(instance, attr, value)
        instance.save()
        return instance

    class Meta:
        model = CustomUser
        fields = (
            'id', 'name', 'password', 'phone',
            'created_at', 'updated_at',
            'is_active', 'is_staff', 'is_superuser' , 'created_at', 'updated_at' , 'session_token' , 'pin'
        )
        extra_kwargs = {
            'password': {'write_only': True},
            'pin' : {'write_only': True, 'required': False},
        }
