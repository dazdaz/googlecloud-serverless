/**
 * Order Service (Node.js)
 * -----------------------
 * This service manages order data and demonstrates how a Node.js-based
 * Cloud Run service can handle authenticated requests from other services.
 */

const express = require('express');
const app = express();

// Middleware
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  if (req.headers.authorization) {
    console.log('  Authorization header present (Bearer token)');
  }
  next();
});

// In-memory order storage (simulating a database)
let orders = [
  {
    id: 'order-001',
    userId: 'user-001',
    items: [
      { product: 'Widget A', quantity: 2, price: 29.99 },
      { product: 'Widget B', quantity: 1, price: 49.99 }
    ],
    total: 109.97,
    status: 'completed',
    createdAt: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000).toISOString()
  },
  {
    id: 'order-002',
    userId: 'user-002',
    items: [
      { product: 'Gadget X', quantity: 1, price: 199.99 }
    ],
    total: 199.99,
    status: 'processing',
    createdAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString()
  },
  {
    id: 'order-003',
    userId: 'user-001',
    items: [
      { product: 'Widget C', quantity: 3, price: 15.99 },
      { product: 'Accessory D', quantity: 2, price: 9.99 }
    ],
    total: 67.95,
    status: 'pending',
    createdAt: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString()
  },
  {
    id: 'order-004',
    userId: 'user-003',
    items: [
      { product: 'Premium Package', quantity: 1, price: 499.99 }
    ],
    total: 499.99,
    status: 'shipped',
    createdAt: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString()
  }
];

// Health check endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'order-service',
    language: 'Node.js',
    status: 'healthy',
    version: '1.0.0'
  });
});

app.get('/health', (req, res) => {
  res.json({
    service: 'order-service',
    language: 'Node.js',
    status: 'healthy',
    version: '1.0.0'
  });
});

// Get all orders
app.get('/orders', (req, res) => {
  const { status, userId } = req.query;
  
  let filteredOrders = [...orders];
  
  // Filter by status if provided
  if (status) {
    filteredOrders = filteredOrders.filter(o => o.status === status);
  }
  
  // Filter by userId if provided
  if (userId) {
    filteredOrders = filteredOrders.filter(o => o.userId === userId);
  }
  
  res.json({
    service: 'order-service (Node.js)',
    count: filteredOrders.length,
    orders: filteredOrders
  });
});

// Get order by ID
app.get('/orders/:orderId', (req, res) => {
  const { orderId } = req.params;
  const order = orders.find(o => o.id === orderId);
  
  if (!order) {
    return res.status(404).json({
      error: `Order with ID '${orderId}' not found`
    });
  }
  
  res.json({
    service: 'order-service (Node.js)',
    order
  });
});

// Get orders by user ID
app.get('/orders/user/:userId', (req, res) => {
  const { userId } = req.params;
  const userOrders = orders.filter(o => o.userId === userId);
  
  res.json({
    service: 'order-service (Node.js)',
    userId,
    count: userOrders.length,
    orders: userOrders
  });
});

// Create a new order
app.post('/orders', (req, res) => {
  const { userId, items } = req.body;
  
  // Validate required fields
  if (!userId) {
    return res.status(400).json({
      error: 'userId is required'
    });
  }
  
  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({
      error: 'items array is required and must not be empty'
    });
  }
  
  // Calculate total
  const total = items.reduce((sum, item) => {
    return sum + (item.price || 0) * (item.quantity || 1);
  }, 0);
  
  // Create new order
  const newOrder = {
    id: `order-${String(orders.length + 1).padStart(3, '0')}`,
    userId,
    items,
    total: Math.round(total * 100) / 100,
    status: 'pending',
    createdAt: new Date().toISOString()
  };
  
  orders.push(newOrder);
  
  res.status(201).json({
    service: 'order-service (Node.js)',
    message: 'Order created successfully',
    order: newOrder
  });
});

// Update order status
app.patch('/orders/:orderId/status', (req, res) => {
  const { orderId } = req.params;
  const { status } = req.body;
  
  const validStatuses = ['pending', 'processing', 'shipped', 'completed', 'cancelled'];
  
  if (!status || !validStatuses.includes(status)) {
    return res.status(400).json({
      error: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
    });
  }
  
  const orderIndex = orders.findIndex(o => o.id === orderId);
  
  if (orderIndex === -1) {
    return res.status(404).json({
      error: `Order with ID '${orderId}' not found`
    });
  }
  
  orders[orderIndex].status = status;
  orders[orderIndex].updatedAt = new Date().toISOString();
  
  res.json({
    service: 'order-service (Node.js)',
    message: 'Order status updated successfully',
    order: orders[orderIndex]
  });
});

// Delete an order
app.delete('/orders/:orderId', (req, res) => {
  const { orderId } = req.params;
  const orderIndex = orders.findIndex(o => o.id === orderId);
  
  if (orderIndex === -1) {
    return res.status(404).json({
      error: `Order with ID '${orderId}' not found`
    });
  }
  
  const deletedOrder = orders.splice(orderIndex, 1)[0];
  
  res.json({
    service: 'order-service (Node.js)',
    message: `Order '${orderId}' deleted successfully`,
    order: deletedOrder
  });
});

// Get order statistics
app.get('/stats', (req, res) => {
  const stats = {
    totalOrders: orders.length,
    totalRevenue: orders.reduce((sum, o) => sum + o.total, 0),
    ordersByStatus: {},
    averageOrderValue: 0
  };
  
  // Count orders by status
  orders.forEach(order => {
    stats.ordersByStatus[order.status] = (stats.ordersByStatus[order.status] || 0) + 1;
  });
  
  // Calculate average order value
  if (orders.length > 0) {
    stats.averageOrderValue = Math.round((stats.totalRevenue / orders.length) * 100) / 100;
  }
  
  stats.totalRevenue = Math.round(stats.totalRevenue * 100) / 100;
  
  res.json({
    service: 'order-service (Node.js)',
    statistics: stats
  });
});

// Start server
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Order Service (Node.js) listening on port ${PORT}`);
});