from django.db import migrations
from api.user.models import CustomUser

class Migration(migrations.Migration):
    def seed_data (apps, schema_editor):
        user = CustomUser(
            name="kygiet",
            email="kygiet@gmail.com",
            is_staff=True,
            is_superuser=True,
            phone="9746894500",  # phone is now required and unique
        )
        user.set_password("lbSHBBK77")
        user.save()

    dependencies = [
        
    ]
    operations = [
        migrations.RunPython(seed_data),
    ]