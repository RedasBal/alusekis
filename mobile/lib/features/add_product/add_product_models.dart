import '../submit_price/submit_price_models.dart';

/// The store the new product's first price is for, known before the form opens.
class AddProductTarget {
  const AddProductTarget({required this.storeId, required this.storeName});

  final int storeId;
  final String storeName;
}

/// A product as the server reports it (id, name, volume).
class ProductRef {
  const ProductRef({required this.id, required this.name, required this.volumeMl});

  factory ProductRef.fromJson(Map<String, dynamic> json) => ProductRef(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        volumeMl: (json['volumeMl'] as num).toInt(),
      );

  final int id;
  final String name;
  final int volumeMl;
}

/// The server's answer to a successful creation: the product and its first price.
class CreatedProduct {
  const CreatedProduct({required this.product, required this.price});

  factory CreatedProduct.fromJson(Map<String, dynamic> json) => CreatedProduct(
        product: ProductRef.fromJson(json['product'] as Map<String, dynamic>),
        price: SubmittedPrice.fromJson(json['price'] as Map<String, dynamic>),
      );

  final ProductRef product;
  final SubmittedPrice price;
}

/// The server found a product with the same name and volume (`product_exists`).
class ProductExistsException implements Exception {
  const ProductExistsException(this.existing);

  final ProductRef existing;

  @override
  String toString() => 'ProductExistsException(${existing.id})';
}
