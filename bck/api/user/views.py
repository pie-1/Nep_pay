from django.shortcuts import render

# Create your views here.
from rest_framework.views import APIView
from rest_framework import viewsets , status
from rest_framework.permissions import IsAuthenticated , AllowAny
from .serializers import UserSerializer
from .models import CustomUser
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.contrib.auth import get_user_model , login , logout
from api.wallet.models import Wallet
import json , re
import random
from rest_framework.response import Response



def generate_session_token(length=10):

    return ''.join(random.SystemRandom().choice([chr(i) for i in range(97,123)]+[str(i) for i in range(0,10)])  for _ in range(length))
@csrf_exempt
def signin(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Invalid request method'}, status=400)

    phone = request.POST.get('phone')
    password = request.POST.get('password')

    if not phone or not phone.isnumeric():
        return JsonResponse({'error': 'Phone must be numeric'}, status=400)

    if not password or len(password) < 3:
        return JsonResponse({'error': 'Password must be at least 3 characters long'}, status=400)

    UserModel = get_user_model()

    try:
        user = UserModel.objects.get(phone=phone)

        if not user.check_password(password):
            return JsonResponse({'error': 'Invalid password'}, status=400)

        if user.session_token != "0":
            # Invalidate previous session (optional: only if you want to enforce single-login)
            user.session_token = "0"
            user.save()
            return JsonResponse({'error': 'User already logged in'}, status=400)

        # Generate and save new session token
        session_token = generate_session_token()
        user.session_token = session_token
        user.save()

        # Log the user in (starts session)
        login(request, user)

        # ✅ Re-fetch updated user data AFTER saving token
        usr_dict = UserModel.objects.filter(pk=user.pk).values().first()
        usr_dict.pop('password', None)  # just in case it's present
        return JsonResponse({'session_token': session_token, 'user': usr_dict}, status=200)

    except UserModel.DoesNotExist:
        return JsonResponse({'error': 'User does not exist'}, status=400)

@csrf_exempt
def signout(request , id):
    logout(request)
    
    UserModel = get_user_model()

    try:
        user = UserModel.objects.get(pk=id)
        user.session_token = "0"
        user.save()
    except UserModel.DoesNotExist:
        return JsonResponse({'error': 'Invalid user ID'})
    
    return JsonResponse({'success':'Logout success'})

class UserViewSet(viewsets.ModelViewSet):
    permission_classes_by_action = {'create' : [AllowAny]}
    queryset = CustomUser.objects.all().order_by('id')
    serializer_class = UserSerializer

    def get_permissions(self):
        try:
            return [permission() for permission in self.permission_classes_by_action[self.action]]
        except KeyError:
            return [permission() for permission in self.permission_classes]
    
    def create(self, request, *args, **kwargs):
        print("📥 [DEBUG] Raw incoming request data:", request.data)

        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid():                                                                                                                                                                                                                                                                                                                  
            print("❌ [DEBUG] Serializer errors:", serializer.errors)
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        self.perform_create(serializer)
        print("✅ [DEBUG] Successfully created user:", serializer.data)

        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)
    

class CreateSuperuserView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        data = request.data
        phone = data.get('phone')
        name = data.get('name', 'Admin')
        password = data.get('password')

        if not phone or not password:
            return Response({'error': 'Phone and password required'}, status=400)

        User = get_user_model()
        if User.objects.filter(phone=phone).exists():
            return Response({'error': 'User already exists'}, status=409)

        user = User.objects.create_superuser(phone=phone, name=name, password=password)
        Wallet.objects.create(user=user)

        return Response({'message': 'Superuser created', 'user_id': user.id})