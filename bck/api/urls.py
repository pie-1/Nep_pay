
from django.contrib import admin
from django.urls import path , include


urlpatterns = [
    path("admin/", admin.site.urls),
    path("sync/", include("api.sync.urls")),
    path("user/" , include("api.user.urls"))
]
