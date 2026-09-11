FROM n8nio/n8n:2.22.6

ENV N8N_COMMUNITY_PACKAGES_ENABLED=true

USER root
RUN mkdir -p /home/node/.n8n/nodes
COPY nodes/package.json /home/node/.n8n/nodes/package.json
RUN cd /home/node/.n8n/nodes && npm install --omit=dev \
    && chown -R node:node /home/node/.n8n
USER node
