from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="StrategyConfig",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("name", models.CharField(max_length=64, unique=True)),
                ("config", models.JSONField(default=dict)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
        ),
        migrations.CreateModel(
            name="BacktestRun",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("strategy_name", models.CharField(default="TwoHunters", max_length=64)),
                ("symbols", models.JSONField(default=list)),
                ("start_date", models.DateField()),
                ("end_date", models.DateField()),
                ("config", models.JSONField(default=dict)),
                ("status", models.CharField(choices=[("pending", "pending"), ("running", "running"), ("completed", "completed"), ("failed", "failed")], default="pending", max_length=16)),
                ("results", models.JSONField(blank=True, default=dict)),
                ("error", models.TextField(blank=True, default="")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={"ordering": ["-created_at"]},
        ),
    ]
