{{/*
Expand the name of the chart.
*/}}
{{- define "opennebula.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "opennebula.fullname" -}}
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
{{- define "opennebula.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "opennebula.labels" -}}
helm.sh/chart: {{ include "opennebula.chart" . }}
{{ include "opennebula.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (immutable - used in StatefulSet selector)
*/}}
{{- define "opennebula.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opennebula.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
MariaDB host - handles both enabled subchart and external DB scenarios
*/}}
{{- define "opennebula.mariadb.host" -}}
{{- if .Values.mariadb.enabled }}
{{- printf "%s-mariadb" (include "opennebula.fullname" .) }}
{{- else }}
{{- required "externalDatabase.host is required when mariadb.enabled=false" .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{/*
MariaDB port
*/}}
{{- define "opennebula.mariadb.port" -}}
{{- if .Values.mariadb.enabled }}
{{- 3306 }}
{{- else }}
{{- .Values.externalDatabase.port | default 3306 }}
{{- end }}
{{- end }}

{{/*
MariaDB database name
*/}}
{{- define "opennebula.mariadb.database" -}}
{{- if .Values.mariadb.enabled }}
{{- .Values.mariadb.auth.database }}
{{- else }}
{{- .Values.externalDatabase.database }}
{{- end }}
{{- end }}

{{/*
MariaDB username
*/}}
{{- define "opennebula.mariadb.username" -}}
{{- if .Values.mariadb.enabled }}
{{- .Values.mariadb.auth.username }}
{{- else }}
{{- .Values.externalDatabase.username }}
{{- end }}
{{- end }}

{{/*
MariaDB secret name - from subchart secret or external secret
*/}}
{{- define "opennebula.mariadb.secretName" -}}
{{- if .Values.mariadb.enabled }}
{{- printf "%s-mariadb" (include "opennebula.fullname" .) }}
{{- else if .Values.externalDatabase.existingSecret }}
{{- .Values.externalDatabase.existingSecret }}
{{- else }}
{{- printf "%s-db-secret" (include "opennebula.fullname" .) }}
{{- end }}
{{- end }}
