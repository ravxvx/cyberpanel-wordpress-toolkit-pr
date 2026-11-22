from django.urls import path
from . import views

# No app_name on purpose: CyberPanel's installer puts {% url 'wordpressToolkitPro' %}
# into the sidebar, so the route must have exactly this global name.
urlpatterns = [
    path("", views.dashboard, name="wordpressToolkitPro"),
    path("deploy/", views.deploy, name="wordpressToolkitProDeploy"),
    path("status/", views.status, name="wordpressToolkitProStatus"),
    path("job/", views.job, name="wordpressToolkitProJob"),
    path("jobstatus/", views.jobstatus, name="wordpressToolkitProJobStatus"),
    path("migrate-upload/", views.migrate_upload, name="wordpressToolkitProMigrateUpload"),
    path("migrate-files/", views.migrate_files, name="wordpressToolkitProMigrateFiles"),
    path("diagnostics/", views.diagnostics, name="wordpressToolkitProDiagnostics"),
    path("system-logs/", views.toolkit_logs, name="wordpressToolkitProSystemLogs"),
]
