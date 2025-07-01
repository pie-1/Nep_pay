# views.py
from django.shortcuts import render
from rest_framework.views import APIView
from rest_framework import viewsets, status
from rest_framework.permissions import IsAuthenticated, AllowAny
from .serializers import UserSerializer
from .models import CustomUser
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.contrib.auth import get_user_model, login, logout
from api.wallet.models import Wallet
import json, re, random
from rest_framework.response import Response
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed
from django.utils.decorators import method_decorator
from django.views import View

# ---------------------- AUTH ----------------------
class SessionTokenAuthentication(BaseAuthentication):
    def authenticate(self, request):
        token = request.META.get('HTTP_SESSION_TOKEN')
        if not token:
            return None
        User = get_user_model()
        try:
            user = User.objects.get(session_token=token)
            return (user, None)
        except User.DoesNotExist:
            raise AuthenticationFailed('Invalid session token')

# ---------------------- HELPERS ----------------------
def generate_session_token(length=10):
    return ''.join(random.SystemRandom().choice(
        [chr(i) for i in range(97,123)]+[str(i) for i in range(0,10)]) for _ in range(length))

# ---------------------- SIGNIN ----------------------
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
            user.session_token = "0"
            user.save()
            return JsonResponse({'error': 'User already logged in'}, status=400)

        session_token = generate_session_token()
        user.session_token = session_token
        user.save()
        login(request, user)

        usr_dict = UserModel.objects.filter(pk=user.pk).values().first()
        usr_dict.pop('password', None)
        return JsonResponse({'session_token': session_token, 'user': usr_dict}, status=200)

    except UserModel.DoesNotExist:
        return JsonResponse({'error': 'User does not exist'}, status=400)

# ---------------------- SIGNOUT ----------------------
@csrf_exempt
def signout(request, id):
    logout(request)
    UserModel = get_user_model()
    try:
        user = UserModel.objects.get(pk=id)
        user.session_token = "0"
        user.save()
    except UserModel.DoesNotExist:
        return JsonResponse({'error': 'Invalid user ID'})
    return JsonResponse({'success':'Logout success'})

# ---------------------- VIEWSETS ----------------------
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
        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        self.perform_create(serializer)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)

# ---------------------- CREATE SUPERUSER ----------------------
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

# ---------------------- ADD PIN ----------------------
@csrf_exempt
def add_pin(request, id):
    if request.method != 'POST':
        return JsonResponse({'error': 'Only POST method allowed'}, status=405)

    session_token = request.headers.get('session-token')
    if not session_token:
        return JsonResponse({'error': 'Session token missing'}, status=401)

    UserModel = get_user_model()
    try:
        user = UserModel.objects.get(session_token=session_token)
    except UserModel.DoesNotExist:
        return JsonResponse({'error': 'Invalid session token'}, status=401)

    if str(user.id) != str(id):
        return JsonResponse({'error': 'Unauthorized access'}, status=403)

    try:
        data = json.loads(request.body)
        pin = data.get('pin')
    except:
        return JsonResponse({'error': 'Invalid JSON body'}, status=400)

    if not pin or not pin.isdigit() or len(pin) not in [4, 6]:
        return JsonResponse({'error': 'PIN must be a 4 or 6 digit number'}, status=400)

    user.pin = pin
    user.save()
    return JsonResponse({'success': 'PIN set successfully'})
