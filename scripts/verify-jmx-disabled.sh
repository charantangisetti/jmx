#!/bin/bash
# Script to verify JMX is completely disabled in Strimzi Kafka deployment

echo "Verifying JMX is disabled in Strimzi Kafka deployment..."
echo "=========================================="

# Function to check JMX in pod
check_jmx_in_pod() {
    local pod_name=$1
    local container=$2
    
    echo ""
    echo "Checking $pod_name (container: $container)..."
    
    # Check JVM arguments
    echo "JVM Arguments:"
    kubectl exec -it $pod_name -n phziot -c $container -- bash -c 'ps aux | grep java' 2>/dev/null | grep -o '\-Dcom\.sun\.management\.jmxremote[^ ]*' || echo "No JMX arguments found"
    
    # Check environment variables
    echo "KAFKA_JMX_OPTS:"
    kubectl exec -it $pod_name -n phziot -c $container -- printenv KAFKA_JMX_OPTS 2>/dev/null || echo "Not set"
    
    # Check if port 9999 is listening
    echo "Port 9999 status:"
    kubectl exec -it $pod_name -n phziot -c $container -- netstat -tlnp 2>/dev/null | grep 9999 || echo "Port 9999 not listening"
}

# Get Kafka pods
echo "Kafka Broker Pods:"
kafka_pods=$(kubectl get pods -n phziot -l strimzi.io/cluster=phziot-kafkacluster,strimzi.io/kind=Kafka -o name | cut -d'/' -f2)
for pod in $kafka_pods; do
    check_jmx_in_pod $pod "kafka"
done

# Get Zookeeper pods
echo ""
echo "=========================================="
echo "Zookeeper Pods:"
zk_pods=$(kubectl get pods -n phziot -l strimzi.io/cluster=phziot-kafkacluster,strimzi.io/name=phziot-kafkacluster-zookeeper -o name | cut -d'/' -f2)
for pod in $zk_pods; do
    check_jmx_in_pod $pod "zookeeper"
done

# Get Kafka Connect pods
echo ""
echo "=========================================="
echo "Kafka Connect Pods:"
connect_pods=$(kubectl get pods -n phziot -l strimzi.io/kind=KafkaConnect -o name | cut -d'/' -f2)
for pod in $connect_pods; do
    check_jmx_in_pod $pod "kafka-connect"
done

echo ""
echo "=========================================="
echo "Verification complete!"
echo ""
echo "Expected results when JMX is disabled:"
echo "- KAFKA_JMX_OPTS should show: -Dcom.sun.management.jmxremote=false"
echo "- Port 9999 should not be listening"
echo "- JVM arguments should show -Dcom.sun.management.jmxremote=false as the LAST occurrence"