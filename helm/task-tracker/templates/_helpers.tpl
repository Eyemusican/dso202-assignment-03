{{/*
_helpers.tpl - named templates shared by every file in templates/.
Files whose names begin with "_" are never rendered as objects.
*/}}

{{/* task-tracker.name: the chart name, at most 63 characters. */}}
{{- define "task-tracker.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* task-tracker.chart: "<name>-<version>", for the helm.sh/chart label. */}}
{{- define "task-tracker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
task-tracker.environment: the environment name.
"required" stops rendering with this message when it is empty,
so no object can be produced without choosing dev or prod.
*/}}
{{- define "task-tracker.environment" -}}
{{- required "environment must be set (dev or prod), use -f environments/<env>.yaml" .Values.environment }}
{{- end }}

{{/*
task-tracker.selectorLabels: the small, stable set that Services and
Deployments select on. Keeps the Assignment 1 "app" label, plus the
release name so two releases never select each other's Pods.
Each template adds its own "tier" label after this.
These must never change after install, because
Deployment.spec.selector is immutable.
*/}}
{{- define "task-tracker.selectorLabels" -}}
app: task-tracker
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* task-tracker.labels: the full label set for every object. */}}
{{- define "task-tracker.labels" -}}
helm.sh/chart: {{ include "task-tracker.chart" . }}
{{ include "task-tracker.selectorLabels" . }}
app.kubernetes.io/name: {{ include "task-tracker.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
dso202/environment: {{ include "task-tracker.environment" . | quote }}
{{- end }}
