# SAST worker, packaged as a Lambda container image.
# Build it from the REPO ROOT (see README Step 5).

# AWS's official base image for Node.js Lambda functions
FROM public.ecr.aws/lambda/nodejs:22

# 1. The provided SAST scanner (unchanged) and its packages
COPY sast/backend/package*.json ${LAMBDA_TASK_ROOT}/sast/
RUN cd ${LAMBDA_TASK_ROOT}/sast && npm install --omit=dev
COPY sast/backend/ ${LAMBDA_TASK_ROOT}/sast/

# 2. Our worker and its packages
COPY workers/sast-worker/package*.json ${LAMBDA_TASK_ROOT}/
RUN cd ${LAMBDA_TASK_ROOT} && npm install --omit=dev
COPY workers/shared/ ${LAMBDA_TASK_ROOT}/shared/
COPY workers/sast-worker/*.js ${LAMBDA_TASK_ROOT}/

# Tells Lambda to run the "handler" function in index.js
CMD ["index.handler"]
