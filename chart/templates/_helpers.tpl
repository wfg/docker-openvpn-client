{{/*
Expand the name of the chart.
*/}}
{{- define "openvpn-client.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "openvpn-client.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "openvpn-client.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "openvpn-client.labels" -}}
helm.sh/chart: {{ include "openvpn-client.chart" . }}
{{ include "openvpn-client.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "openvpn-client.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openvpn-client.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Convert boolean to on/off
*/}}
{{- define "openvpn-client.boolean" -}}
{{- if .enabled }} "on" {{- else }} "off" {{- end }}
{{- end }}

{{/*
Define auth secret name
*/}}
{{- define "openvpn-client.authSecretName" -}}
{{- if .Values.auth.existingSecret -}}
    {{- .Values.auth.existingSecret -}}
{{- else -}}
    {{- include "openvpn-client.fullname" . | printf "%s-auth" }}
{{- end -}}
{{- end -}}

{{/*
Define config secret name
*/}}
{{- define "openvpn-client.configSecretName" -}}
    {{- include "openvpn-client.fullname" . | printf "%s-config" }}
{{- end -}}
