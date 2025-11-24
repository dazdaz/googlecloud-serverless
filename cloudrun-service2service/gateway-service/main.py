"""
Gateway Service (Python)
------------------------
This service acts as the entry point and orchestrator for the microservices architecture.
It demonstrates Cloud Run service-to-service authentication using OIDC ID tokens.

Service Mesh Communication:
- Gateway -> User Service
- Gateway -> Order Service  
- Gateway -> User Service -> Order Service (nested call)
"""
import os
import json
import requests
from flask import Flask, request, jsonify
import google.auth.transport.requests
import google.oauth2.id_token

app = Flask(__name__)

# Service URLs - populated from environment variables
USER_SERVICE_URL = os.environ.get('USER_SERVICE_URL', '')
ORDER_SERVICE_URL = os.environ.get('ORDER_SERVICE_URL', '')


def get_id_token(audience: str) -> str:
    """
    Get an OIDC ID token for service-to-service authentication.
    This token is used to authenticate requests to other Cloud Run services.
    
    The token is a JWT with:
    - iss: https://accounts.google.com
    - aud: The target service URL
    - sub: The service account email
    - exp: Expiration time
    """
    auth_req = google.auth.transport.requests.Request()
    id_token = google.oauth2.id_token.fetch_id_token(auth_req, audience)
    return id_token


def make_authenticated_request(url: str, method: str = 'GET', data: dict = None) -> dict:
    """
    Make an authenticated HTTP request to another Cloud Run service.
    Uses OIDC ID tokens for authentication.
    """
    # Get the base URL (audience) for the ID token
    audience = url.split('/')[0] + '//' + url.split('/')[2]
    
    # Get OIDC ID token for authentication
    id_token = get_id_token(audience)
    
    headers = {
        'Authorization': f'Bearer {id_token}',
        'Content-Type': 'application/json'
    }
    
    if method == 'GET':
        response = requests.get(url, headers=headers, timeout=30)
    elif method == 'POST':
        response = requests.post(url, headers=headers, json=data, timeout=30)
    else:
        raise ValueError(f"Unsupported HTTP method: {method}")
    
    response.raise_for_status()
    return response.json()


@app.route('/', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({
        'service': 'gateway-service',
        'language': 'Python',
        'status': 'healthy',
        'version': '1.0.0',
        'mesh': {
            'gateway': 'public',
            'user_service': 'internal' if USER_SERVICE_URL else 'not configured',
            'order_service': 'internal' if ORDER_SERVICE_URL else 'not configured'
        }
    })


@app.route('/api/users', methods=['GET'])
def get_users():
    """
    Fetch users from the User Service (Go).
    Demonstrates: Gateway -> User Service
    """
    if not USER_SERVICE_URL:
        return jsonify({'error': 'USER_SERVICE_URL not configured'}), 500
    
    try:
        result = make_authenticated_request(f'{USER_SERVICE_URL}/users')
        return jsonify({
            'source': 'gateway-service (Python)',
            'target': 'user-service (Go)',
            'flow': 'Gateway → User Service',
            'data': result
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/users/<user_id>', methods=['GET'])
def get_user(user_id):
    """
    Fetch a specific user from the User Service.
    """
    if not USER_SERVICE_URL:
        return jsonify({'error': 'USER_SERVICE_URL not configured'}), 500
    
    try:
        result = make_authenticated_request(f'{USER_SERVICE_URL}/users/{user_id}')
        return jsonify({
            'source': 'gateway-service (Python)',
            'target': 'user-service (Go)',
            'flow': 'Gateway → User Service',
            'data': result
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/orders', methods=['GET'])
def get_orders():
    """
    Fetch orders from the Order Service (Node.js).
    Demonstrates: Gateway -> Order Service
    """
    if not ORDER_SERVICE_URL:
        return jsonify({'error': 'ORDER_SERVICE_URL not configured'}), 500
    
    try:
        result = make_authenticated_request(f'{ORDER_SERVICE_URL}/orders')
        return jsonify({
            'source': 'gateway-service (Python)',
            'target': 'order-service (Node.js)',
            'flow': 'Gateway → Order Service',
            'data': result
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/orders', methods=['POST'])
def create_order():
    """
    Create a new order via the Order Service.
    Demonstrates authenticated POST requests.
    """
    if not ORDER_SERVICE_URL:
        return jsonify({'error': 'ORDER_SERVICE_URL not configured'}), 500
    
    try:
        order_data = request.get_json() or {}
        result = make_authenticated_request(
            f'{ORDER_SERVICE_URL}/orders',
            method='POST',
            data=order_data
        )
        return jsonify({
            'source': 'gateway-service (Python)',
            'target': 'order-service (Node.js)',
            'flow': 'Gateway → Order Service',
            'data': result
        }), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/aggregate', methods=['GET'])
def aggregate_data():
    """
    Aggregate data from all services.
    Demonstrates calling multiple services in sequence.
    Flow: Gateway -> User Service + Gateway -> Order Service
    """
    result = {
        'source': 'gateway-service (Python)',
        'flow': 'Gateway → [User Service, Order Service]',
        'aggregated_data': {}
    }
    
    errors = []
    
    # Fetch users
    if USER_SERVICE_URL:
        try:
            users = make_authenticated_request(f'{USER_SERVICE_URL}/users')
            result['aggregated_data']['users'] = {
                'service': 'user-service (Go)',
                'data': users
            }
        except Exception as e:
            errors.append(f'User service error: {str(e)}')
    else:
        errors.append('USER_SERVICE_URL not configured')
    
    # Fetch orders
    if ORDER_SERVICE_URL:
        try:
            orders = make_authenticated_request(f'{ORDER_SERVICE_URL}/orders')
            result['aggregated_data']['orders'] = {
                'service': 'order-service (Node.js)',
                'data': orders
            }
        except Exception as e:
            errors.append(f'Order service error: {str(e)}')
    else:
        errors.append('ORDER_SERVICE_URL not configured')
    
    if errors:
        result['errors'] = errors
    
    return jsonify(result)


@app.route('/api/user-orders/<user_id>', methods=['GET'])
def get_user_orders(user_id):
    """
    Get user and their orders using the SERVICE MESH pattern.
    This demonstrates: Gateway -> User Service -> Order Service
    
    The User Service will internally call the Order Service to fetch 
    orders for the user, demonstrating service-to-service communication
    between internal services.
    """
    result = {
        'source': 'gateway-service (Python)',
        'workflow': 'user-orders-mesh'
    }
    
    if not USER_SERVICE_URL:
        return jsonify({'error': 'USER_SERVICE_URL not configured'}), 500
    
    try:
        # Call User Service's /users/{id}/orders endpoint
        # This endpoint triggers: User Service -> Order Service
        mesh_result = make_authenticated_request(f'{USER_SERVICE_URL}/users/{user_id}/orders')
        
        result['flow'] = 'Gateway → User Service → Order Service'
        result['data'] = mesh_result
        result['mesh_path'] = [
            'gateway-service (Python)',
            'user-service (Go)',
            'order-service (Node.js)'
        ]
        
        return jsonify(result)
    
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            return jsonify({'error': f'User {user_id} not found'}), 404
        return jsonify({'error': str(e)}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/user-orders-direct/<user_id>', methods=['GET'])
def get_user_orders_direct(user_id):
    """
    Get user and their orders using DIRECT calls from Gateway.
    This demonstrates: Gateway -> User Service + Gateway -> Order Service
    (NOT using the service mesh pattern)
    
    Compare this with /api/user-orders/<user_id> which uses the mesh pattern.
    """
    result = {
        'source': 'gateway-service (Python)',
        'workflow': 'user-orders-direct',
        'flow': 'Gateway → User Service + Gateway → Order Service'
    }
    
    if not USER_SERVICE_URL or not ORDER_SERVICE_URL:
        return jsonify({'error': 'Services not configured'}), 500
    
    try:
        # Step 1: Fetch user directly from User Service
        user = make_authenticated_request(f'{USER_SERVICE_URL}/users/{user_id}')
        result['user'] = {
            'service': 'user-service (Go)',
            'path': 'Gateway → User Service',
            'data': user
        }
        
        # Step 2: Fetch orders directly from Order Service
        orders = make_authenticated_request(f'{ORDER_SERVICE_URL}/orders/user/{user_id}')
        result['orders'] = {
            'service': 'order-service (Node.js)',
            'path': 'Gateway → Order Service',
            'data': orders
        }
        
        return jsonify(result)
    
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            return jsonify({'error': f'User {user_id} not found'}), 404
        return jsonify({'error': str(e)}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)