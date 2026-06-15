{{/*
Common labels applied to every Microservices resource.
*/}}
{{- define "microservices.labels" -}}
app.kubernetes.io/part-of: jenkins-2026
app.kubernetes.io/managed-by: {{ .Release.Service }}
jenkins2026.io/env: {{ .Values.env }}
{{- end -}}

{{/*
Ingress class name for the selected platform. global.platform is set via
--set by vars/microservicesDeploy.groovy from config/config.yaml platform.target.
*/}}
{{- define "microservices.ingressClassName" -}}
{{- $platform := .Values.global.platform -}}
{{- if eq $platform "gke" -}}
gce
{{- else if eq $platform "eks" -}}
alb
{{- else if eq $platform "aks" -}}
webapprouting.kubernetes.azure.com
{{- else -}}
{{ .Values.ingress.className }}
{{- end -}}
{{- end -}}
