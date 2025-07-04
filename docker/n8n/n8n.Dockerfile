FROM n8nio/n8n

USER root
RUN apk add --no-cache \
  poppler-utils \
  bash \
  coreutils \
  pandoc \
  html2text \
  unrtf \
  tesseract-ocr
USER node