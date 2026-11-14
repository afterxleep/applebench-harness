import UIKit

final class ContactCell: UITableViewCell {
    static let reuseIdentifier = "ContactCell"

    private let nameLabel = UILabel()
    private let avatarView = UIImageView()

    /// The avatar currently displayed (exposed for verification).
    var avatarImage: UIImage? { avatarView.image }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)
        contentView.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with contact: Contact, loader: any AvatarLoading) {
        nameLabel.text = contact.name
        loader.loadAvatar(for: contact.id) { image in
            self.avatarView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
    }
}
