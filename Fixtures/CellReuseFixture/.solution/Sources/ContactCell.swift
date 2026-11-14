import UIKit

final class ContactCell: UITableViewCell {
    static let reuseIdentifier = "ContactCell"

    private let nameLabel = UILabel()
    private let avatarView = UIImageView()

    /// The contact this cell currently represents. Avatar loads that finish
    /// after the cell has been reused belong to a different contact and are
    /// dropped.
    private var displayedContactID: Int?

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
        displayedContactID = contact.id
        loader.loadAvatar(for: contact.id) { [weak self] image in
            guard let self, self.displayedContactID == contact.id else { return }
            self.avatarView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        avatarView.image = nil
        displayedContactID = nil
    }
}
